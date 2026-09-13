import SwiftUI

/// Capsule tag for a single anime genre. Genres without a mapped icon render
/// as text-only tags.
struct GenreTag: View {
    let genre: String

    var body: some View {
        Pill(text: genre, systemImage: GenreIcon.systemImage(for: genre))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(genre)
    }
}

/// Maps Kitsu category titles to representative SF Symbols. Unmapped genres
/// return `nil` so tags never fall back to a generic icon.
enum GenreIcon {
    static func systemImage(for genre: String) -> String? {
        let key = genre
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return symbols[key]
    }

    private static let symbols: [String: String] = [
        "action": "flame.fill",
        "adventure": "map.fill",
        "anthropomorphic": "pawprint.fill",
        "award winning": "trophy.fill",
        "cars": "car.fill",
        "comedy": "face.smiling.fill",
        "coming of age": "sun.horizon.fill",
        "cooking": "fork.knife",
        "crime": "building.columns.fill",
        "cyberpunk": "cpu.fill",
        "delinquents": "person.fill.xmark",
        "demons": "flame.circle.fill",
        "detective": "magnifyingglass",
        "drama": "theatermasks.fill",
        "dystopian": "building.2.fill",
        "ecchi": "flame.fill",
        "educational": "book.fill",
        "fantasy": "wand.and.stars",
        "gag humor": "face.smiling.fill",
        "game": "gamecontroller.fill",
        "ghosts": "cloud.fog.fill",
        "gore": "drop.fill",
        "harem": "person.3.fill",
        "historical": "scroll.fill",
        "horror": "moon.fill",
        "idol": "mic.fill",
        "isekai": "door.left.hand.open",
        "iyashikei": "leaf.fill",
        "josei": "person.crop.circle.fill",
        "kids": "teddybear.fill",
        "love polygon": "heart.circle.fill",
        "magic": "wand.and.rays",
        "mahou shoujo": "wand.and.rays",
        "martial arts": "figure.martial.arts",
        "mecha": "gearshape.2.fill",
        "medical": "stethoscope",
        "military": "shield.fill",
        "music": "music.note",
        "mystery": "magnifyingglass",
        "ninja": "wind",
        "parody": "mustache.fill",
        "performing arts": "theatermasks.fill",
        "pets": "pawprint.fill",
        "police": "shield.lefthalf.filled",
        "post-apocalyptic": "tornado",
        "psychological": "brain.head.profile",
        "racing": "flag.checkered",
        "reincarnation": "arrow.triangle.2.circlepath",
        "romance": "heart.fill",
        "samurai": "figure.fencing",
        "school": "graduationcap.fill",
        "sci-fi": "atom",
        "science fiction": "atom",
        "seinen": "person.crop.circle.fill",
        "shoujo": "heart.circle.fill",
        "shounen": "bolt.circle.fill",
        "showbiz": "star.fill",
        "slice of life": "cup.and.saucer.fill",
        "space": "moon.stars.fill",
        "sports": "figure.run",
        "steampunk": "wrench.and.screwdriver.fill",
        "strategy game": "dice.fill",
        "super power": "bolt.fill",
        "supernatural": "sparkles",
        "survival": "tent.fill",
        "team sports": "sportscourt.fill",
        "thriller": "eye.fill",
        "time travel": "clock.arrow.circlepath",
        "vampire": "drop.fill",
        "video game": "gamecontroller.fill",
        "villainess": "crown.fill",
        "visual arts": "paintpalette.fill",
        "work life": "briefcase.fill",
        "zombies": "figure.walk",
    ]
}

/// Picks the most representative genres for compact displays.
enum GenreSelection {
    static let maxCount = 4

    /// Orders genres by a curated significance ranking, preserving the source
    /// order for equally-ranked entries, then caps the result.
    static func featured(from genres: [String], limit: Int = maxCount) -> [String] {
        genres.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(of: lhs.element)
                let rhsRank = rank(of: rhs.element)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element)
    }

    private static func rank(of genre: String) -> Int {
        let key = genre
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return priority[key] ?? Int.max
    }

    private static let priority: [String: Int] = Dictionary(
        uniqueKeysWithValues: [
            "action",
            "adventure",
            "comedy",
            "drama",
            "fantasy",
            "sci-fi",
            "science fiction",
            "romance",
            "slice of life",
            "supernatural",
            "mystery",
            "horror",
            "thriller",
            "sports",
            "music",
            "mecha",
            "psychological",
            "school",
            "historical",
            "isekai",
            "shounen",
            "shoujo",
            "seinen",
            "josei",
        ].enumerated().map { ($0.element, $0.offset) }
    )
}
