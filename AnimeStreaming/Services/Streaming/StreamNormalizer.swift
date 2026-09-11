import Foundation

struct StreamNormalizer: Sendable {
    private let matcher = EpisodeMatcher()

    func normalize(_ raw: RawStreamResult) -> StreamCandidate {
        makeCandidate(from: raw, match: nil)
    }

    func normalize(
        _ raw: RawStreamResult,
        matching context: EpisodeMatcher.Context
    ) -> StreamCandidate {
        let parsed = ReleaseParser.parse(raw.displayTitle)
        let match = matcher.match(parsed, context: context)
        return makeCandidate(from: raw, match: match)
    }

    func normalize(
        _ raws: [RawStreamResult],
        matching context: EpisodeMatcher.Context
    ) -> [StreamCandidate] {
        raws.map { normalize($0, matching: context) }
    }

    private func makeCandidate(
        from raw: RawStreamResult,
        match: EpisodeMatchResult?
    ) -> StreamCandidate {
        let parsed = ReleaseParser.parse(raw.displayTitle)
        let hash = raw.infoHash?.lowercased()
        let magnetHash = raw.magnetURI.flatMap { StreamDeduplicator.hash(fromMagnet: $0.absoluteString) }
        let identity = hash
            ?? magnetHash
            ?? raw.directURL?.absoluteString
            ?? "\(raw.addonID)|\(raw.displayTitle)"

        return StreamCandidate(
            id: identity,
            addonID: raw.addonID,
            addonName: raw.addonName,
            displayTitle: raw.displayTitle,
            rawTitle: raw.rawTitle,
            infoHash: hash,
            magnetURI: raw.magnetURI,
            directURL: raw.directURL,
            fileIndex: raw.fileIndex,
            resolution: parsed.resolution,
            codec: parsed.codec,
            source: parsed.source,
            releaseGroup: parsed.releaseGroup,
            sizeBytes: raw.sizeBytes,
            seeders: raw.seeders,
            audioLanguages: parsed.audioLanguages.union(Self.languages(from: raw.providerMetadata["audio"])),
            subtitleLanguages: parsed.subtitleLanguages.union(Self.languages(from: raw.providerMetadata["subtitles"])),
            parsedEpisode: ParsedEpisodeInfo(
                season: parsed.season,
                episode: parsed.episode,
                isBatch: parsed.isBatch,
                isSpecial: parsed.isSpecial
            ),
            isBatch: parsed.isBatch,
            debridStatus: .unknown,
            episodeMatchConfidence: match?.confidence ?? 0,
            targetEpisode: match?.matchedEpisode
        )
    }

    static func languages(from value: String?) -> Set<String> {
        guard let value else { return [] }
        let lowered = value.lowercased()
        return Set(knownLanguages.filter { lowered.contains($0) })
    }

    private static let knownLanguages = [
        "japanese", "english", "spanish", "french", "german",
        "italian", "portuguese", "russian", "korean", "chinese",
    ]
}
