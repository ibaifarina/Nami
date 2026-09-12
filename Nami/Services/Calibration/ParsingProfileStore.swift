import CryptoKit
import Foundation

/// One addon's persisted calibration state.
struct StoredAddonParsingProfile: Codable, Hashable, Sendable {
    var fingerprint: AddonFingerprint
    var episode: ContentParsingProfile?
    var movie: ContentParsingProfile?
    var status: AddonCalibrationStatus
    var calibratedAt: Date
    var observations: [RuntimeParseObservation]
    var isStale: Bool

    init(
        fingerprint: AddonFingerprint,
        episode: ContentParsingProfile? = nil,
        movie: ContentParsingProfile? = nil,
        status: AddonCalibrationStatus,
        calibratedAt: Date = Date(),
        observations: [RuntimeParseObservation] = [],
        isStale: Bool = false
    ) {
        self.fingerprint = fingerprint
        self.episode = episode
        self.movie = movie
        self.status = status
        self.calibratedAt = calibratedAt
        self.observations = observations
        self.isStale = isStale
    }

    func contentProfile(for kind: StreamContentKind) -> ContentParsingProfile? {
        let profile = kind == .movie ? movie : episode
        guard let profile, !profile.isEmpty else { return nil }
        return profile
    }

    var bestCoverage: Double? {
        [episode?.coverage, movie?.coverage].compactMap { $0 }.max()
    }
}

/// A single playback-time parse-coverage measurement for one addon batch.
struct RuntimeParseObservation: Codable, Hashable, Sendable {
    let kind: StreamContentKind
    let matched: Int
    let total: Int
    let date: Date

    var ratio: Double {
        total > 0 ? Double(matched) / Double(total) : 0
    }
}

/// Compact calibration state shown in the Addons settings UI.
struct AddonCalibrationSummary: Hashable, Sendable {
    let addonID: String
    let status: AddonCalibrationStatus
    let coverage: Double?
    let isStale: Bool
    let calibratedAt: Date?
}

/// File-backed store for `StoredAddonParsingProfile` values.
///
/// Profiles are keyed by `AddonFingerprint`, so changing an addon's
/// configuration naturally produces a different key and the old profile is no
/// longer used. The stored file contains only the digest, never raw URLs.
actor ParsingProfileStore {
    enum StalenessPolicy {
        static let windowSize = 6
        static let minimumObservations = 3
        static let minimumSamples = 12
        /// Coverage below this (after enough evidence) marks a profile stale.
        static let staleThreshold = 0.4
        /// Coverage above this clears a stale marker again.
        static let recoveryThreshold = 0.55
        /// A calibrated profile must have been decent to be considered stale.
        static let minimumCalibratedCoverage = 0.5
    }

    private var records: [String: StoredAddonParsingProfile] = [:]
    private let directory: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastPersistedAt: Date = .distantPast

    /// - Parameter directory: disk directory for persisted profiles. Pass
    ///   `nil` for an in-memory store (tests/previews).
    init(directory: URL? = ParsingProfileStore.defaultDirectory()) {
        self.directory = directory
        records = Self.loadRecords(from: directory)
    }

    func profile(for fingerprint: AddonFingerprint) -> StoredAddonParsingProfile? {
        records[fingerprint.storageKey]
    }

    func contentProfile(
        for kind: StreamContentKind,
        fingerprint: AddonFingerprint
    ) -> ContentParsingProfile? {
        records[fingerprint.storageKey]?.contentProfile(for: kind)
    }

    /// Saves a freshly calibrated profile and drops older configurations of the
    /// same addon host so stale profiles cannot linger.
    func save(_ record: StoredAddonParsingProfile) {
        for (key, existing) in records
        where key != record.fingerprint.storageKey
            && existing.fingerprint.addonID == record.fingerprint.addonID
            && existing.fingerprint.host == record.fingerprint.host {
            records[key] = nil
            removeFile(for: key)
        }
        records[record.fingerprint.storageKey] = record
        persist(record, for: record.fingerprint.storageKey)
    }

    func remove(fingerprint: AddonFingerprint) {
        records[fingerprint.storageKey] = nil
        removeFile(for: fingerprint.storageKey)
    }

    func removeAll(addonID: String) {
        for (key, record) in records where record.fingerprint.addonID == addonID {
            records[key] = nil
            removeFile(for: key)
        }
    }

    /// Records playback-time parse coverage. A profile is only marked stale
    /// after several low-coverage batches, never after one unusual stream.
    @discardableResult
    func recordObservation(
        fingerprint: AddonFingerprint,
        kind: StreamContentKind,
        matched: Int,
        total: Int,
        now: Date = Date()
    ) -> StoredAddonParsingProfile? {
        guard total > 0, var record = records[fingerprint.storageKey] else { return nil }
        record.observations.append(
            RuntimeParseObservation(kind: kind, matched: matched, total: total, date: now)
        )
        record.observations = Array(record.observations.suffix(StalenessPolicy.windowSize * 2))
        updateStaleness(&record)
        records[fingerprint.storageKey] = record
        if Date().timeIntervalSince(lastPersistedAt) > 60 || record.isStale {
            persist(record, for: fingerprint.storageKey)
        }
        return record
    }

    func summary(for fingerprint: AddonFingerprint) -> AddonCalibrationSummary? {
        guard let record = records[fingerprint.storageKey] else { return nil }
        return AddonCalibrationSummary(
            addonID: record.fingerprint.addonID,
            status: record.status,
            coverage: record.bestCoverage,
            isStale: record.isStale,
            calibratedAt: record.calibratedAt
        )
    }

    private func updateStaleness(_ record: inout StoredAddonParsingProfile) {
        guard record.status == .success || record.status == .partial else {
            record.isStale = false
            return
        }
        let window = record.observations.suffix(StalenessPolicy.windowSize)
        let samples = window.reduce(0) { $0 + $1.total }
        guard window.count >= StalenessPolicy.minimumObservations,
              samples >= StalenessPolicy.minimumSamples,
              let calibratedCoverage = record.bestCoverage,
              calibratedCoverage >= StalenessPolicy.minimumCalibratedCoverage
        else {
            return
        }
        let matched = window.reduce(0) { $0 + $1.matched }
        let ratio = Double(matched) / Double(max(samples, 1))
        if ratio < StalenessPolicy.staleThreshold {
            record.isStale = true
        } else if ratio > StalenessPolicy.recoveryThreshold {
            record.isStale = false
        }
    }

    // MARK: - Disk

    static func defaultDirectory() -> URL? {
        guard
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            return nil
        }
        return support
            .appending(path: "Nami", directoryHint: .isDirectory)
            .appending(path: "ParsingProfiles", directoryHint: .isDirectory)
    }

    private static func loadRecords(from directory: URL?) -> [String: StoredAddonParsingProfile] {
        guard let directory else { return [:] }
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else {
            return [:]
        }
        let decoder = JSONDecoder()
        var result: [String: StoredAddonParsingProfile] = [:]
        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let record = try? decoder.decode(StoredAddonParsingProfile.self, from: data)
            else {
                continue
            }
            result[record.fingerprint.storageKey] = record
        }
        return result
    }

    private func persist(_ record: StoredAddonParsingProfile, for key: String) {
        lastPersistedAt = Date()
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(record)
            try data.write(to: fileURL(for: key, in: directory), options: .atomic)
        } catch {
            AppLogger.addons.error("Failed to persist addon parsing profile")
        }
    }

    private func removeFile(for key: String) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(for: key, in: directory))
    }

    private func fileURL(for key: String, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }
}
