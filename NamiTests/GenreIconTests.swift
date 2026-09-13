import Testing
@testable import Nami

struct GenreIconTests {
    @Test func mapsKnownGenres() {
        #expect(GenreIcon.systemImage(for: "Action") == "flame.fill")
        #expect(GenreIcon.systemImage(for: "Slice of Life") == "cup.and.saucer.fill")
        #expect(GenreIcon.systemImage(for: "Sci-Fi") == "atom")
    }

    @Test func normalizesCaseAndWhitespace() {
        #expect(GenreIcon.systemImage(for: "  COMEDY  ") == "face.smiling.fill")
    }

    @Test func unmappedGenreHasNoIcon() {
        #expect(GenreIcon.systemImage(for: "Kaiju") == nil)
        #expect(GenreIcon.systemImage(for: "") == nil)
    }
}

struct GenreSelectionTests {
    @Test func capsFeaturedGenres() {
        let genres = ["Action", "Ecchi", "Comedy", "Drama", "Fantasy", "Romance"]
        #expect(GenreSelection.featured(from: genres).count == GenreSelection.maxCount)
    }

    @Test func ranksSignificantGenresFirst() {
        let genres = ["Ecchi", "Harem", "Comedy", "Romance"]
        #expect(GenreSelection.featured(from: genres) == ["Comedy", "Romance", "Ecchi", "Harem"])
    }

    @Test func preservesSourceOrderForUnrankedGenres() {
        let genres = ["Ecchi", "Harem", "Isekai"]
        #expect(GenreSelection.featured(from: genres) == ["Isekai", "Ecchi", "Harem"])
    }

    @Test func emptyGenresStayEmpty() {
        #expect(GenreSelection.featured(from: []).isEmpty)
    }
}
