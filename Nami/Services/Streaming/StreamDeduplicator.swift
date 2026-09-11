import Foundation

struct StreamDeduplicator: Sendable {
    struct Outcome: Sendable {
        let candidates: [StreamCandidate]
        let duplicateCount: Int
    }

    func deduplicate(_ candidates: [StreamCandidate]) -> Outcome {
        var output: [StreamCandidate] = []
        var indexByKey: [String: Int] = [:]
        var duplicateCount = 0

        for candidate in candidates {
            guard let key = Self.dedupeKey(for: candidate) else {
                output.append(candidate)
                continue
            }
            if let existingIndex = indexByKey[key] {
                output[existingIndex] = Self.merge(output[existingIndex], candidate)
                duplicateCount += 1
            } else {
                indexByKey[key] = output.count
                output.append(candidate)
            }
        }

        return Outcome(candidates: output, duplicateCount: duplicateCount)
    }

    static func dedupeKey(for candidate: StreamCandidate) -> String? {
        if let hash = normalizedHash(candidate.infoHash) {
            return "hash:\(hash)"
        }
        if let magnet = candidate.magnetURI?.absoluteString, let hash = hash(fromMagnet: magnet) {
            return "hash:\(hash)"
        }
        if let url = candidate.directURL?.absoluteString.lowercased(), !url.isEmpty {
            return "url:\(url)"
        }
        let title = ReleaseParser.normalizedTitle(for: candidate.rawTitle ?? candidate.displayTitle)
        guard !title.isEmpty else { return nil }
        let size = candidate.sizeBytes.map(String.init) ?? "-"
        let episode = candidate.parsedEpisode?.episode.map(String.init) ?? "-"
        return "fallback:\(title)|\(size)|\(episode)"
    }

    static func normalizedHash(_ hash: String?) -> String? {
        guard let hash else { return nil }
        let cleaned = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.count >= 8, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return cleaned
    }

    static func hash(fromMagnet magnet: String) -> String? {
        guard
            let groups = ReleaseParser.firstMatch("urn:btih:([a-z0-9]+)", in: magnet),
            let hash = groups[safe: 1] ?? nil
        else {
            return nil
        }
        return normalizedHash(hash)
    }

    static func merge(_ base: StreamCandidate, _ other: StreamCandidate) -> StreamCandidate {
        StreamCandidate(
            id: base.id,
            addonID: base.addonID,
            addonName: base.addonName,
            displayTitle: base.displayTitle,
            rawTitle: base.rawTitle ?? other.rawTitle,
            infoHash: base.infoHash ?? other.infoHash,
            magnetURI: base.magnetURI ?? other.magnetURI,
            directURL: base.directURL ?? other.directURL,
            fileIndex: base.fileIndex ?? other.fileIndex,
            resolution: base.resolution ?? other.resolution,
            codec: base.codec ?? other.codec,
            source: base.source ?? other.source,
            releaseGroup: base.releaseGroup ?? other.releaseGroup,
            sizeBytes: base.sizeBytes ?? other.sizeBytes,
            seeders: maxOptional(base.seeders, other.seeders),
            audioLanguages: base.audioLanguages.union(other.audioLanguages),
            subtitleLanguages: base.subtitleLanguages.union(other.subtitleLanguages),
            parsedEpisode: base.parsedEpisode ?? other.parsedEpisode,
            isBatch: base.isBatch || other.isBatch,
            debridStatus: base.debridStatus == .unknown ? other.debridStatus : base.debridStatus,
            episodeMatchConfidence: max(base.episodeMatchConfidence, other.episodeMatchConfidence),
            targetEpisode: base.targetEpisode ?? other.targetEpisode,
            sources: mergedSources(base.sources, other.sources)
        )
    }

    private static func mergedSources(
        _ base: [StreamSource],
        _ other: [StreamSource]
    ) -> [StreamSource] {
        var result = base
        var seen = Set(base.map(\.addonID))
        for source in other where seen.insert(source.addonID).inserted {
            result.append(source)
        }
        return result
    }

    private static func maxOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (let lhs?, let rhs?): max(lhs, rhs)
        case (let lhs?, nil): lhs
        case (nil, let rhs?): rhs
        case (nil, nil): nil
        }
    }
}
