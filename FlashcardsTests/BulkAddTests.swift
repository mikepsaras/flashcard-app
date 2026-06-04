import Testing
@testable import Flashcards

@MainActor
@Suite struct BulkAddTests {
    @Test func splitsTabSeparatedLinesIntoCards() {
        let rows = BulkAddView.parsePaste("hola\thello\nadiós\tbye")
        #expect(rows.count == 2)
        #expect(rows[0].term == "hola")
        #expect(rows[0].definition == "hello")
        #expect(rows[1].term == "adiós")
        #expect(rows[1].definition == "bye")
    }

    @Test func splitsOnFirstCommaWhenNoTab() {
        let rows = BulkAddView.parsePaste("Japan, Tokyo\nPeru, Lima, capital")
        #expect(rows[0].term == "Japan")
        #expect(rows[0].definition == "Tokyo")
        // Only the FIRST comma splits, so any later commas stay in the definition.
        #expect(rows[1].term == "Peru")
        #expect(rows[1].definition == "Lima, capital")
    }

    @Test func tabTakesPrecedenceOverComma() {
        let rows = BulkAddView.parsePaste("a, b\tc")
        #expect(rows.count == 1)
        #expect(rows[0].term == "a, b")
        #expect(rows[0].definition == "c")
    }

    @Test func lineWithoutDelimiterIsTermOnly() {
        let rows = BulkAddView.parsePaste("Tokyo\nParis")
        #expect(rows.map(\.term) == ["Tokyo", "Paris"])
        #expect(rows.allSatisfy { $0.definition.isEmpty })
    }

    @Test func blankLinesAreDropped() {
        let rows = BulkAddView.parsePaste("a\tb\n\n\nc\td\n")
        #expect(rows.count == 2)
    }
}
