import Foundation

/// Progress reported while an addon is being calibrated.
enum AddonCalibrationPhase: Hashable, Sendable {
    case preparing
    case collecting(title: String, index: Int, total: Int)
    case analyzing
    case validating
}

/// Result of one calibration attempt, including the copy the UI shows.
struct AddonCalibrationReport: Identifiable, Hashable, Sendable {
    let id: String
    let addonID: String
    let addonName: String
    let fingerprint: AddonFingerprint
    let status: AddonCalibrationStatus
    let coverage: Double?
    let episodeCoverage: Double?
    let movieCoverage: Double?
    let title: String
    let message: String
}

/// Orchestrates calibration: collects a bounded sample set, asks the on-device
/// model for reusable rules, validates them against the samples, and persists a
/// deterministic parsing profile for this exact addon configuration.
///
/// Playback never calls this service. Normal playback only reads the saved
/// profile through `ParsingProfileStore`.
actor AddonCalibrationService {
    private enum FallbackReason {
        case analyzerUnavailable
        case noSampleStreams
        case analysisFailed
    }

    enum Limits {
        static let episodeSamplesPerTitle = 5
        static let movieSamplesPerTitle = 5
        static let episodeTargetSamples = 8
        static let episodeTargetDiversity = 6
        static let movieTargetSamples = 5
        static let movieTargetDiversity = 4
        /// Calibration requests are allowed to outlive normal playback
        /// discovery. Aggregating addons can need several seconds to run live
        /// scrapers, and a timeout here used to make a slow response look like
        /// an unsupported stream format.
        static let requestTimeout = Duration.seconds(20)
        /// The on-device model can take a minute to load and answer on first
        /// use on older Apple silicon, so this is deliberately generous.
        static let analysisTimeout = Duration.seconds(150)
        static let successCoverage = 0.6
        static let partialCoverage = 0.25
    }

    /// The on-device model has a fixed, small context window, so only a
    /// representative subset of the collected samples is sent to it for
    /// analysis. Validation still runs against every collected sample.
    /// Attempts are tried in order until one fits the model's context window.
    enum AnalysisLimits {
        static let attempts: [(episodes: Int, movies: Int)] = [
            (3, 2),
            (2, 1),
            (1, 1),
        ]
    }

    private let addonManager: AddonManager
    private let profileStore: ParsingProfileStore
    private let analyzer: (any StreamFormatAnalyzing)?
    private let selector = CalibrationSampleSelector()
    private let validator = ProfileValidator()
    private let converter = LearnedRuleConverter()

    init(
        addonManager: AddonManager,
        profileStore: ParsingProfileStore,
        analyzer: (any StreamFormatAnalyzing)? = AddonCalibrationService.defaultAnalyzer()
    ) {
        self.addonManager = addonManager
        self.profileStore = profileStore
        self.analyzer = analyzer
    }

    /// Returns the on-device analyzer when Apple's FoundationModels framework
    /// is present and the model is ready; otherwise `nil` so installation
    /// proceeds with built-in best-effort parsing.
    static func defaultAnalyzer() -> (any StreamFormatAnalyzing)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelStreamFormatAnalyzer()
        }
        #endif
        return nil
    }

    // MARK: - Calibration

    func calibrate(
        addon: InstalledAddon,
        force: Bool = false,
        progress: @Sendable (AddonCalibrationPhase) async -> Void = { _ in }
    ) async -> AddonCalibrationReport {
        let fingerprint = AddonFingerprint(addonID: addon.id, manifestURL: addon.manifestURL)

        if BuiltInAddonFormats.isOptimized(addon) {
            let record = StoredAddonParsingProfile(
                fingerprint: fingerprint,
                status: .skipped
            )
            await profileStore.save(record)
            return Self.report(
                for: addon,
                fingerprint: fingerprint,
                status: .skipped,
                episodeCoverage: nil,
                movieCoverage: nil,
                coverage: nil
            )
        }

        if !force,
           let existing = await profileStore.profile(for: fingerprint),
           existing.fingerprint.parserVersion == AddonFingerprint.currentParserVersion {
            return Self.report(
                for: addon,
                fingerprint: fingerprint,
                status: existing.status,
                episodeCoverage: existing.episode?.coverage,
                movieCoverage: existing.movie?.coverage,
                coverage: existing.bestCoverage
            )
        }

        await progress(.preparing)

        // Episode and movie sampling run as two bounded, independent chains.
        // Each chain stays sequential (adaptive fallbacks depend on what was
        // collected), keeping total concurrency at two addon requests.
        async let episodeSamples = collect(
            addon: addon,
            kind: .episode,
            titles: CalibrationCatalog.episodeTitles,
            perTitleLimit: Limits.episodeSamplesPerTitle,
            targetSamples: Limits.episodeTargetSamples,
            targetDiversity: Limits.episodeTargetDiversity,
            progress: progress
        )
        async let movieSamples = collect(
            addon: addon,
            kind: .movie,
            titles: CalibrationCatalog.movieTitles,
            perTitleLimit: Limits.movieSamplesPerTitle,
            targetSamples: Limits.movieTargetSamples,
            targetDiversity: Limits.movieTargetDiversity,
            progress: progress
        )
        let batch = await CalibrationSampleBatch(
            episodes: episodeSamples,
            movies: movieSamples
        )

        guard !batch.isEmpty else {
            // An empty probe says nothing about the addon's response format.
            // It can be caused by provider filters, temporary upstream
            // availability, or simply no releases for the fixed setup titles.
            return await saveUnavailable(
                addon: addon,
                fingerprint: fingerprint,
                reason: .noSampleStreams
            )
        }

        guard let analyzer, analyzer.isAvailable else {
            return await saveUnavailable(
                addon: addon,
                fingerprint: fingerprint,
                reason: .analyzerUnavailable
            )
        }

        await progress(.analyzing)
        let learned: LearnedStreamFormat
        do {
            let analyzed = try await withTimeout(Limits.analysisTimeout) {
                try await Self.analyze(analyzer, batch: batch)
            }
            guard let analyzed else {
                // Every bounded attempt still overflowed the model's context
                // window. That is a model limitation, not an addon format
                // problem, so fall back to built-in parsing.
                return await saveUnavailable(
                    addon: addon,
                    fingerprint: fingerprint,
                    reason: .analysisFailed
                )
            }
            learned = analyzed
        } catch is CancellationError {
            return Self.report(
                for: addon,
                fingerprint: fingerprint,
                status: .failure,
                episodeCoverage: nil,
                movieCoverage: nil,
                coverage: nil
            )
        } catch {
            return await saveUnavailable(
                addon: addon,
                fingerprint: fingerprint,
                reason: .analysisFailed,
                underlyingError: error
            )
        }

        await progress(.validating)
        var episodeProfile: ContentParsingProfile?
        var movieProfile: ContentParsingProfile?
        if !batch.episodes.isEmpty {
            let candidate = converter.convert(learned.episodeRules, kind: .episode)
            let result = validator.validate(candidate, samples: batch.episodes)
            if !result.profile.isEmpty { episodeProfile = result.profile }
        }
        if !batch.movies.isEmpty {
            let candidate = converter.convert(learned.movieRules, kind: .movie)
            let result = validator.validate(candidate, samples: batch.movies)
            if !result.profile.isEmpty { movieProfile = result.profile }
        }

        let profiles = [episodeProfile, movieProfile].compactMap { $0 }
        let coverage = Self.weightedCoverage(profiles)
        let status: AddonCalibrationStatus
        if profiles.isEmpty {
            status = .failure
        } else if coverage >= Limits.successCoverage {
            status = .success
        } else if coverage >= Limits.partialCoverage {
            status = .partial
        } else {
            status = .failure
        }

        let record = StoredAddonParsingProfile(
            fingerprint: fingerprint,
            episode: episodeProfile,
            movie: movieProfile,
            status: status
        )
        await profileStore.save(record)

        return Self.report(
            for: addon,
            fingerprint: fingerprint,
            status: status,
            episodeCoverage: episodeProfile?.coverage,
            movieCoverage: movieProfile?.coverage,
            coverage: coverage
        )
    }

    func removeProfile(for addon: InstalledAddon) async {
        let fingerprint = AddonFingerprint(addonID: addon.id, manifestURL: addon.manifestURL)
        await profileStore.remove(fingerprint: fingerprint)
    }

    func removeProfile(fingerprint: AddonFingerprint) async {
        await profileStore.remove(fingerprint: fingerprint)
    }

    func summaries(for addons: [InstalledAddon]) async -> [String: AddonCalibrationSummary] {
        var result: [String: AddonCalibrationSummary] = [:]
        for addon in addons {
            let fingerprint = AddonFingerprint(addonID: addon.id, manifestURL: addon.manifestURL)
            if let summary = await profileStore.summary(for: fingerprint) {
                result[addon.id] = summary
            }
        }
        return result
    }

    // MARK: - Sampling

    private func collect(
        addon: InstalledAddon,
        kind: StreamContentKind,
        titles: [CalibrationTitle],
        perTitleLimit: Int,
        targetSamples: Int,
        targetDiversity: Int,
        progress: @Sendable (AddonCalibrationPhase) async -> Void
    ) async -> [CalibrationSample] {
        var samples: [CalibrationSample] = []
        var signatures: Set<StreamFeatureSignature> = []
        for (index, title) in titles.enumerated() {
            if Task.isCancelled { break }
            if index > 0 {
                // Fallback titles are only fetched while the sample set is thin
                // or lacks diversity, keeping requests bounded.
                guard samples.count < targetSamples || signatures.count < targetDiversity
                else {
                    break
                }
            }
            await progress(
                .collecting(title: title.displayName, index: index + 1, total: titles.count)
            )
            let episode = kind == .movie
                ? CalibrationCatalog.movie(for: title)
                : CalibrationCatalog.episode(for: title)
            let result = await addonManager.query(
                addon: addon,
                for: title.identity,
                episode: episode,
                titles: title.titles,
                year: title.year,
                isMovie: kind == .movie,
                timeout: Limits.requestTimeout
            )
            let candidates = result.streams.map { raw in
                CalibrationSample(
                    titleName: title.displayName,
                    kind: kind,
                    fields: raw.profileFields,
                    sizeBytes: raw.sizeBytes,
                    seeders: raw.seeders
                )
            }
            for sample in selector.select(from: candidates, limit: perTitleLimit) {
                let signature = sample.featureSignature
                guard signatures.insert(signature).inserted else { continue }
                samples.append(sample)
            }
        }
        return samples
    }

    // MARK: - Model input

    /// Runs the analyzer against progressively smaller sample subsets until the
    /// prompt fits the model's context window. Empty and failed generations
    /// also get a smaller retry because those are often model/context issues,
    /// not evidence that the addon's format is unsupported. Returns `nil`
    /// when every attempt exceeded the context window.
    private static func analyze(
        _ analyzer: any StreamFormatAnalyzing,
        batch: CalibrationSampleBatch
    ) async throws -> LearnedStreamFormat? {
        var lastEmptyResult: LearnedStreamFormat?
        var lastGenerationError: StreamFormatAnalyzerError?
        for limits in AnalysisLimits.attempts {
            let subset = analysisBatch(
                from: batch,
                episodeLimit: limits.episodes,
                movieLimit: limits.movies
            )
            guard !subset.isEmpty else { continue }
            do {
                let learned = try await analyzer.analyze(subset)
                if learned.episodeRules.isEmpty, learned.movieRules.isEmpty {
                    lastEmptyResult = learned
                    continue
                }
                return learned
            } catch StreamFormatAnalyzerError.inputTooLarge {
                continue
            } catch let error as StreamFormatAnalyzerError {
                if case .generationFailed = error {
                    lastGenerationError = error
                    continue
                }
                throw error
            }
        }
        if let lastEmptyResult { return lastEmptyResult }
        if let lastGenerationError { throw lastGenerationError }
        return nil
    }

    static func analysisBatch(
        from batch: CalibrationSampleBatch,
        episodeLimit: Int,
        movieLimit: Int
    ) -> CalibrationSampleBatch {
        CalibrationSampleBatch(
            episodes: spread(batch.episodes, limit: episodeLimit),
            movies: spread(batch.movies, limit: movieLimit)
        )
    }

    /// Round-robins across titles so a small prompt still spans the whole
    /// corpus (modern, long-running, and season-based releases) instead of
    /// taking every sample from the first title.
    static func spread(_ samples: [CalibrationSample], limit: Int) -> [CalibrationSample] {
        guard limit > 0 else { return [] }
        guard samples.count > limit else { return samples }
        var buckets: [String: [CalibrationSample]] = [:]
        var titleOrder: [String] = []
        for sample in samples {
            if buckets[sample.titleName] == nil { titleOrder.append(sample.titleName) }
            buckets[sample.titleName, default: []].append(sample)
        }
        var result: [CalibrationSample] = []
        var index = 0
        while result.count < limit {
            var picked = false
            for title in titleOrder {
                guard let bucket = buckets[title], index < bucket.count else { continue }
                result.append(bucket[index])
                picked = true
                if result.count == limit { break }
            }
            guard picked else { break }
            index += 1
        }
        return result
    }

    private func saveUnavailable(
        addon: InstalledAddon,
        fingerprint: AddonFingerprint,
        reason: FallbackReason,
        underlyingError: Error? = nil
    ) async -> AddonCalibrationReport {
        let record = StoredAddonParsingProfile(fingerprint: fingerprint, status: .unavailable)
        await profileStore.save(record)
        if let underlyingError {
            AppLogger.addons.error(
                "Format analysis could not finish; built-in parsing will be used: \(String(describing: type(of: underlyingError)))"
            )
        } else {
            AppLogger.addons.notice(
                "Format analysis was unavailable; built-in parsing will be used"
            )
        }
        return Self.report(
            for: addon,
            fingerprint: fingerprint,
            status: .unavailable,
            episodeCoverage: nil,
            movieCoverage: nil,
            coverage: nil,
            fallbackReason: reason
        )
    }

    private static func weightedCoverage(_ profiles: [ContentParsingProfile]) -> Double {
        let totalSamples = profiles.reduce(0) { $0 + $1.sampleCount }
        guard totalSamples > 0 else { return 0 }
        let weighted = profiles.reduce(0.0) {
            $0 + $1.coverage * Double($1.sampleCount)
        }
        return weighted / Double(totalSamples)
    }

    // MARK: - Reporting

    private static func report(
        for addon: InstalledAddon,
        fingerprint: AddonFingerprint,
        status: AddonCalibrationStatus,
        episodeCoverage: Double?,
        movieCoverage: Double?,
        coverage: Double?,
        fallbackReason: FallbackReason? = nil
    ) -> AddonCalibrationReport {
        let copy = Self.copy(for: status, fallbackReason: fallbackReason)
        return AddonCalibrationReport(
            id: fingerprint.storageKey,
            addonID: addon.id,
            addonName: addon.name,
            fingerprint: fingerprint,
            status: status,
            coverage: coverage,
            episodeCoverage: episodeCoverage,
            movieCoverage: movieCoverage,
            title: copy.title,
            message: copy.message
        )
    }

    private static func copy(
        for status: AddonCalibrationStatus,
        fallbackReason: FallbackReason? = nil
    ) -> (title: String, message: String) {
        switch status {
        case .success:
            (
                "Addon ready",
                "Nami successfully identified this addon's stream format."
            )
        case .partial:
            (
                "Addon installed with limited compatibility",
                "Nami could identify some stream information, but not all of it. Playback should still work, but automatic source selection may be less accurate."
            )
        case .failure:
            (
                "Addon format not recognized",
                "Nami couldn't reliably interpret this addon's stream results. The addon may still work, but automatic source selection may be less accurate."
            )
        case .unavailable:
            switch fallbackReason {
            case .noSampleStreams:
                (
                    "Addon installed",
                    "The addon didn't return streams for Nami's setup titles, so its format couldn't be analyzed. It will use the built-in parser; you can recalibrate later from Addons settings."
                )
            case .analysisFailed:
                (
                    "Addon installed",
                    "On-device format analysis couldn't finish, so Nami will use its built-in parser instead. Playback still works; automatic source selection may be slightly less accurate."
                )
            case .analyzerUnavailable, nil:
                (
                    "Addon installed",
                    "Nami couldn't run on-device format analysis for this addon, so it will use its built-in parser instead. Playback works normally; automatic source selection may be slightly less accurate."
                )
            }
        case .skipped:
            (
                "Addon installed",
                "Nami already understands this addon's format and will use its optimized parser."
            )
        }
    }
}
