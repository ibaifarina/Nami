import Foundation

/// Turns raw addon results into `StreamCandidate`s.
///
/// Structured addon fields always win. The generic release parser runs on the
/// release title, and — when a calibrated profile exists for the addon — the
/// deterministic profile parser fills in metadata the generic parser missed.
/// Unknown metadata merely stays unknown.
struct StreamNormalizer: Sendable {
    private let matcher = EpisodeMatcher()
    private let profileParser = ProfileStreamParser()

    func normalize(
        _ raw: RawStreamResult,
        profile: ContentParsingProfile? = nil
    ) -> StreamCandidate {
        makeCandidate(from: raw, match: nil, profile: profile)
    }

    func normalize(
        _ raw: RawStreamResult,
        matching context: EpisodeMatcher.Context,
        profile: ContentParsingProfile? = nil
    ) -> StreamCandidate {
        let parsed = ReleaseParser.parse(raw.displayTitle)
        let match = matcher.match(parsed, context: context)
        return makeCandidate(from: raw, match: match, profile: profile)
    }

    func normalize(
        _ raws: [RawStreamResult],
        matching context: EpisodeMatcher.Context,
        profile: ContentParsingProfile? = nil
    ) -> [StreamCandidate] {
        raws.map { normalize($0, matching: context, profile: profile) }
    }

    private func makeCandidate(
        from raw: RawStreamResult,
        match: EpisodeMatchResult?,
        profile: ContentParsingProfile?
    ) -> StreamCandidate {
        let extraction = profile.map {
            profileParser.parse(fields: raw.profileFields, profile: $0)
        }
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
            resolution: Self.resolution(from: raw.providerMetadata["quality"])
                ?? parsed.resolution
                ?? extraction?.resolution,
            codec: parsed.codec ?? extraction?.codec,
            dynamicRange: parsed.dynamicRange ?? extraction?.dynamicRange,
            source: parsed.source ?? extraction?.source,
            releaseGroup: raw.providerMetadata["group"]
                ?? parsed.releaseGroup
                ?? extraction?.releaseGroup,
            sizeBytes: raw.sizeBytes ?? parsed.sizeBytes ?? extraction?.sizeBytes,
            seeders: raw.seeders ?? parsed.seeders ?? extraction?.seeders,
            isCachedHint: extraction?.isCached ?? false,
            audioLanguages: parsed.audioLanguages
                .union(Self.languages(from: raw.providerMetadata["audio"]))
                .union(extraction?.audioLanguages ?? []),
            subtitleLanguages: parsed.subtitleLanguages
                .union(Self.languages(from: raw.providerMetadata["subtitles"]))
                .union(extraction?.subtitleLanguages ?? []),
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
        return Set(LanguageVocabulary.known.filter { lowered.contains($0) })
    }

    /// Structured addon quality strings (for example `"1080p"` from the
    /// generic protocol) take priority over text inference.
    static func resolution(from value: String?) -> VideoResolution? {
        guard let value else { return nil }
        return ProfileValueNormalizer.videoResolution(value)
    }
}
