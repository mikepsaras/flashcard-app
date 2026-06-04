import Testing
@testable import Flashcards

@MainActor
@Suite struct BulkAddTests {
    // MARK: parsePaste (Pairs mode)

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
        #expect(BulkAddView.parseLines("x\n\n  \ny") == ["x", "y"])
    }

    // MARK: draftCards (per-mode build)

    @Test func pairsModeDropsBlankFronts() {
        let drafts = BulkAddView.draftCards(
            mode: .pairs, rows: [("a", "1"), ("  ", "2"), ("c", "3")],
            sharedFront: "", sharedBack: "")
        #expect(drafts.count == 2)
        #expect(drafts.map { $0.front } == ["a", "c"])
        #expect(drafts.map { $0.back } == ["1", "3"])
    }

    @Test func sameBackAppliesSharedBackToEveryFront() {
        // The headline example: several cards whose back is "Germany".
        let drafts = BulkAddView.draftCards(
            mode: .sameBack, rows: [("Berlin", ""), ("largest economy", ""), ("  ", "")],
            sharedFront: "", sharedBack: "Germany")
        #expect(drafts.count == 2)                              // blank front dropped
        #expect(drafts.allSatisfy { $0.back == "Germany" })
        #expect(drafts.map { $0.front } == ["Berlin", "largest economy"])
    }

    @Test func sameFrontAppliesSharedFrontToEveryBack() {
        let drafts = BulkAddView.draftCards(
            mode: .sameFront, rows: [("", "Berlin"), ("", "Munich"), ("", "  ")],
            sharedFront: "A German city", sharedBack: "")
        #expect(drafts.count == 2)                              // blank back dropped
        #expect(drafts.allSatisfy { $0.front == "A German city" })
        #expect(drafts.map { $0.back } == ["Berlin", "Munich"])
    }
}
