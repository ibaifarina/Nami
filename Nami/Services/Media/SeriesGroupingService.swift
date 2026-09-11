import Foundation

/// Builds viewer-facing `AnimeSeries` groups from Kitsu's separate anime
/// records. Grouping is driven by Kitsu `mediaRelationships`, never by titles.
///
/// Only direct prequel/sequel chains of TV entries become seasons. Movies,
/// OVAs, ONAs, specials, side stories and spin-offs stay under `related`.
struct SeriesGroupingService: Sendable {
    private let repository: any MediaRepository
    private let maxNodes: Int

    init(repository: any MediaRepository, maxNodes: Int = 30) {
        self.repository = repository
        self.maxNodes = maxNodes
    }

    func series(for anime: Anime, details: AnimeDetails) async -> AnimeSeries {
        var nodes: [String: Anime] = [details.anime.id: details.anime]
        var detailsByID: [String: AnimeDetails] = [details.anime.id: details]
        var after: [String: String] = [:]
        var relatedByID: [String: AnimeRelation] = [:]

        var visited: Set<String> = [details.anime.id]
        var queue: [String] = [details.anime.id]

        while !queue.isEmpty, visited.count < maxNodes {
            let currentID = queue.removeFirst()
            let currentDetails: AnimeDetails
            if let cached = detailsByID[currentID] {
                currentDetails = cached
            } else if let fetched = try? await repository.anime(id: currentID) {
                detailsByID[currentID] = fetched
                currentDetails = fetched
            } else {
                continue
            }

            for relation in currentDetails.relations {
                let targetID = relation.anime.id
                if nodes[targetID] == nil {
                    nodes[targetID] = relation.anime
                }
                if relation.role.isSequentialInstallment {
                    if relation.role == .sequel {
                        if after[currentDetails.anime.id] == nil {
                            after[currentDetails.anime.id] = targetID
                        }
                    } else if relation.role == .prequel, after[targetID] == nil {
                        after[targetID] = currentDetails.anime.id
                    }
                    if !visited.contains(targetID), visited.count < maxNodes {
                        visited.insert(targetID)
                        queue.append(targetID)
                    }
                } else if relatedByID[targetID] == nil {
                    relatedByID[targetID] = relation
                }
            }
        }

        let chain = Self.buildChain(from: nodes, after: after, fallback: anime)
        var installments: [AnimeInstallment] = []
        var offset = 0
        var related = relatedByID

        for node in chain where node.subtype == .tv {
            let order = installments.count
            installments.append(
                AnimeInstallment(
                    anime: node,
                    relationship: order == 0 ? .original : .sequel,
                    displayOrder: order,
                    displayName: Self.displayName(for: node, order: order, chain: chain),
                    absoluteEpisodeOffset: offset
                )
            )
            offset += max(node.episodeCount ?? 0, 0)
        }

        for node in chain where node.subtype != .tv {
            if related[node.id] == nil {
                related[node.id] = AnimeRelation(role: .sequel, anime: node)
            }
        }

        if installments.isEmpty {
            installments = [
                AnimeInstallment(
                    anime: anime,
                    relationship: .original,
                    displayOrder: 0,
                    displayName: Self.displayName(for: anime, order: 0, chain: [anime]),
                    absoluteEpisodeOffset: 0
                ),
            ]
        }

        let root = chain.first ?? anime
        let installmentIDs = Set(installments.map(\.id))
        let relatedList = related.values
            .filter { !installmentIDs.contains($0.anime.id) }
            .sorted {
                let lhs = Self.relatedPriority($0.role)
                let rhs = Self.relatedPriority($1.role)
                if lhs != rhs { return lhs < rhs }
                return $0.anime.title < $1.anime.title
            }

        return AnimeSeries(rootAnime: root, installments: installments, related: relatedList)
    }

    /// Orders nodes following the normalized `after` map, starting from a node
    /// with no predecessor. Unreachable branches are ignored; the fallback is
    /// used when no chain can be built.
    static func buildChain(
        from nodes: [String: Anime],
        after: [String: String],
        fallback: Anime
    ) -> [Anime] {
        guard !nodes.isEmpty else { return [fallback] }
        let predecessors = Set(after.values)
        // Only nodes in the sequential graph can start the chain; isolated
        // related media (OVAs, movies, side stories) must not win the sort.
        let starts = nodes.keys
            .filter { id in
                !predecessors.contains(id) && (after[id] != nil || id == fallback.id)
            }
            .compactMap { nodes[$0] }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    switch (lhs.startDate, rhs.startDate) {
                    case let (l?, r?): return l < r
                    case (nil, _?): return false
                    case (_?, nil): return true
                    default: break
                    }
                }
                return lhs.id < rhs.id
            }
        guard var current = starts.first else {
            return nodes[fallback.id].map { [$0] } ?? [fallback]
        }
        var chain: [Anime] = [current]
        var seen: Set<String> = [current.id]
        while let nextID = after[current.id], let next = nodes[nextID], seen.insert(nextID).inserted {
            chain.append(next)
            current = next
        }
        return chain
    }

    static func displayName(for anime: Anime, order: Int, chain: [Anime]) -> String {
        let title = anime.canonicalTitle ?? anime.englishTitle ?? anime.title
        if title.localizedCaseInsensitiveContains("final season") {
            return "Final Season"
        }
        let base = chain.first.flatMap { seasonNumber(inTitle: $0.canonicalTitle ?? $0.title) } ?? 1
        return "Season \(base + order)"
    }

    /// Extracts an explicit season number from a title, e.g.
    /// "Boku no Hero Academia 2nd Season" -> 2, "Attack on Titan Season 3" -> 3.
    /// Used only for display naming; never for grouping.
    static func seasonNumber(inTitle title: String) -> Int? {
        let patterns = [
            #"(\d{1,2})(?:st|nd|rd|th)\s+Season"#,
            #"Season\s+(\d{1,2})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            guard let match = regex.firstMatch(in: title, options: [], range: range) else { continue }
            let captureRange = match.range(at: 1)
            guard
                let swiftRange = Range(captureRange, in: title),
                let value = Int(title[swiftRange])
            else {
                continue
            }
            return value
        }
        return nil
    }

    private static func relatedPriority(_ role: MediaRelationRole) -> Int {
        switch role {
        case .prequel, .sequel: 0
        case .sideStory: 1
        case .spinOff: 2
        case .alternativeVersion, .alternativeSetting: 3
        case .parentStory, .fullStory: 4
        case .summary: 5
        case .adaptation: 6
        case .character, .other: 7
        }
    }
}
