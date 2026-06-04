import Testing
@testable import Flashcards

@MainActor
@Suite struct BulkAddTests {
    @Test func splitsTabSeparatedLinesIntoCards() {
        let rows = BulkAddView.parsePaste("hola\thello\nadiós\tbye")
        #expect(rows.count == 2)
        #expect(rows[0].front == "hola")
        #expect(rows[0].back == "hello")
        #expect(rows[1].front == "adiós")
        #expect(rows[1].back == "bye")
    }

    @Test func splitsOnFirstCommaWhenNoTab() {
        let rows = BulkAddView.parsePaste("Japan, Tokyo\nPeru, Lima, capital")
        #expect(rows[0].front == "Japan")
        #expect(rows[0].back == "Tokyo")
        // Only the FIRST comma splits, so later commas stay in the back.
        #expect(rows[1].front == "Peru")
        #expect(rows[1].back == "Lima, capital")
    }

    @Test func tabTakesPrecedenceOverComma() {
        let rows = BulkAddView.parsePaste("a, b\tc")
        #expect(rows.count == 1)
        #expect(rows[0].front == "a, b")
        #expect(rows[0].back == "c")
    }

    @Test func lineWithoutDelimiterIsFrontOnly() {
        let rows = BulkAddView.parsePaste("Tokyo\nParis")
        #expect(rows.map { $0.front } == ["Tokyo", "Paris"])
        #expect(rows.allSatisfy { $0.back.isEmpty })
    }

    @Test func blankLinesAreDropped() {
        #expect(BulkAddView.parsePaste("a\tb\n\n\nc\td").count == 2)
    }
}
