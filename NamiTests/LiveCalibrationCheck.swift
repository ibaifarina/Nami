import Foundation
import Testing
@testable import Nami

/// Live verification of the addon calibration pipeline against a real addon
/// and the on-device FoundationModels analyzer. Disabled by default; run with:
///
///   LIVE_CALIBRATION=1 LIVE_MANIFEST_URL=<addon manifest url> xcodebuild test ...
///
/// When `LIVE_MANIFEST_URL` is unset it falls back to the public TorrentClaw
/// manifest.
struct LiveCalibrationCheck {
    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVE_CALIBRATION"] == "1"
    }

    private var manifestURL: URL {
        let raw = ProcessInfo.processInfo.environment["LIVE_MANIFEST_URL"]
            ?? "https://torrentclaw.com/api/stremio/manifest.json"
        return URL(string: raw)!
    }

    @Test func calibratesRealAddon() async throws {
        guard isEnabled, #available(macOS 26.0, *) else { return }

        let preview = try await AddonInstallService().preview(manifestURL: manifestURL)
        let addon = preview.makeInstalledAddon(priority: 0)
        print("[LIVE] addon: \(addon.name) base=\(addon.baseURL) namespaces=\(addon.idNamespaces) types=\(addon.supportedTypes)")

        let client = KitsuClient()
        let cache = MetadataCache(directory: nil)
        let resolver = MediaIdentityResolver(
            client: client,
            cache: cache,
            imdbResolver: IMDbResolver(http: URLSessionHTTPClient(), cache: cache)
        )
        let manager = AddonManager(identityResolver: resolver)
        let store = ParsingProfileStore(directory: nil)
        let service = AddonCalibrationService(
            addonManager: manager,
            profileStore: store,
            analyzer: AddonCalibrationService.defaultAnalyzer()
        )

        let report = await service.calibrate(addon: addon, force: true) { phase in
            print("[LIVE] phase: \(phase)")
        }
        print("[LIVE] status=\(report.status) title=\(report.title) coverage=\(String(describing: report.coverage))")
        print("[LIVE] message=\(report.message)")
        #expect(report.status != .unavailable, "Analyzer missing; cannot exercise the model path")

        let fingerprint = AddonFingerprint(addonID: addon.id, manifestURL: addon.manifestURL)
        if let stored = await store.profile(for: fingerprint) {
            for (label, profile) in [("episode", stored.episode), ("movie", stored.movie)] {
                guard let profile else { continue }
                print("[LIVE] stored \(label) coverage=\(profile.coverage) rules=\(profile.rules.count)")
                for rule in profile.rules {
                    print("[LIVE] stored \(label) attr=\(rule.attribute) field=\(rule.field) kind=\(rule.kind) pattern=\(rule.pattern) value=\(rule.value ?? "-")")
                }
            }
        }
    }

    /// Reproduces the exact batch shape the service sends to the model so the
    /// context-window behavior can be inspected directly.
    @Test func analysesRealBatch() async throws {
        guard isEnabled, #available(macOS 26.0, *) else { return }

        let preview = try await AddonInstallService().preview(manifestURL: manifestURL)
        let addon = preview.makeInstalledAddon(priority: 0)
        let client = KitsuClient()
        let cache = MetadataCache(directory: nil)
        let resolver = MediaIdentityResolver(
            client: client,
            cache: cache,
            imdbResolver: IMDbResolver(http: URLSessionHTTPClient(), cache: cache)
        )
        let manager = AddonManager(identityResolver: resolver)
        let selector = CalibrationSampleSelector()

        var episodes: [CalibrationSample] = []
        var movies: [CalibrationSample] = []
        for title in CalibrationCatalog.episodeTitles {
            let result = await manager.query(
                addon: addon,
                for: title.identity,
                episode: CalibrationCatalog.episode(for: title),
                titles: title.titles,
                year: title.year,
                isMovie: false
            )
            let candidates = result.streams.map {
                CalibrationSample(
                    titleName: title.displayName,
                    kind: .episode,
                    fields: $0.profileFields,
                    sizeBytes: $0.sizeBytes,
                    seeders: $0.seeders
                )
            }
            episodes.append(contentsOf: selector.select(from: candidates, limit: 5))
        }
        for title in CalibrationCatalog.movieTitles {
            let result = await manager.query(
                addon: addon,
                for: title.identity,
                episode: CalibrationCatalog.movie(for: title),
                titles: title.titles,
                year: title.year,
                isMovie: true
            )
            let candidates = result.streams.map {
                CalibrationSample(
                    titleName: title.displayName,
                    kind: .movie,
                    fields: $0.profileFields,
                    sizeBytes: $0.sizeBytes,
                    seeders: $0.seeders
                )
            }
            movies.append(contentsOf: selector.select(from: candidates, limit: 5))
        }
        let batch = CalibrationSampleBatch(episodes: episodes, movies: movies)
        let prompt = StreamFormatPrompt.make(batch: batch)
        print("[LIVE] batch episodes=\(episodes.count) movies=\(movies.count) promptChars=\(prompt.count)")

        let analyzer = FoundationModelStreamFormatAnalyzer()
        print("[LIVE] analyzer available: \(analyzer.isAvailable)")
        for limits in AddonCalibrationService.AnalysisLimits.attempts {
            let subset = AddonCalibrationService.analysisBatch(
                from: batch,
                episodeLimit: limits.episodes,
                movieLimit: limits.movies
            )
            let subsetPrompt = StreamFormatPrompt.make(batch: subset)
            let start = Date()
            do {
                let learned = try await analyzer.analyze(subset)
                print(
                    "[LIVE] attempt \(limits.episodes)+\(limits.movies) chars=\(subsetPrompt.count) "
                        + "took=\(String(format: "%.1f", Date().timeIntervalSince(start)))s "
                        + "epRules=\(learned.episodeRules.count) movieRules=\(learned.movieRules.count)"
                )
                for rule in learned.episodeRules + learned.movieRules {
                    print("[LIVE] rule attr=\(rule.attribute) field=\(rule.sourceField) patterns=\(rule.patterns) value=\(rule.value ?? "-")")
                }
                break
            } catch {
                print(
                    "[LIVE] attempt \(limits.episodes)+\(limits.movies) chars=\(subsetPrompt.count) "
                        + "took=\(String(format: "%.1f", Date().timeIntervalSince(start)))s "
                        + "error=\(error)"
                )
            }
        }
    }
}
