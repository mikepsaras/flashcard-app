import Testing
import Foundation
@testable import Flashcards

@MainActor
@Suite struct CSVTests {

    @Test func parsesSimpleRows() {
        let rows = CSVCodec.parse("Term,Definition\nSprint,A time-box\nScrum,A framework\n")
        #expect(rows.count == 2)
        #expect(rows[0] == CSVCodec.Row(term: "Sprint", definition: "A time-box"))
        #expect(rows[1].term == "Scrum")
    }

    @Test func skipsHeaderRow() {
        let rows = CSVCodec.parse("term,definition\nA,B\n")
        #expect(rows.count == 1)
        #expect(rows[0] == CSVCodec.Row(term: "A", definition: "B"))
    }

    @Test func handlesQuotedCommasAndNewlines() {
        let rows = CSVCodec.parse("Term,Definition\n\"User, Stories\",\"line1\nline2\"\n")
        #expect(rows.count == 1)
        #expect(rows[0].term == "User, Stories")
        #expect(rows[0].definition == "line1\nline2")
    }

    @Test func handlesEscapedQuotes() {
        let rows = CSVCodec.parse("a,\"He said \"\"hi\"\"\"\n")
        #expect(rows.count == 1)
        #expect(rows[0].definition == "He said \"hi\"")
    }

    @Test func ignoresBlankLines() {
        let rows = CSVCodec.parse("A,B\n\n\nC,D\n")
        #expect(rows.count == 2)
    }

    @Test func leadingBlankLineDoesNotImportHeaderAsCard() {
        let rows = CSVCodec.parse("\nTerm,Definition\nSprint,A time-box\n")
        #expect(rows == [CSVCodec.Row(term: "Sprint", definition: "A time-box")])
    }

    @Test func handlesCRLFLineEndings() {
        // Windows / Excel exports use CRLF. Compare the whole array (no indexing) so a
        // regression fails cleanly instead of trapping on an out-of-bounds subscript.
        let rows = CSVCodec.parse("Term,Definition\r\nSprint,A time-box\r\nScrum,A framework\r\n")
        #expect(rows == [
            CSVCodec.Row(term: "Sprint", definition: "A time-box"),
            CSVCodec.Row(term: "Scrum", definition: "A framework"),
        ])
    }

    @Test func exportEscapesSpecialCharacters() {
        let csv = CSVCodec.export([Card(term: "a,b", definition: "quote\"x")])
        #expect(csv.contains("\"a,b\""))
        #expect(csv.contains("\"quote\"\"x\""))
    }

    @Test func preservesLeadingAndTrailingWhitespace() {
        // Whitespace-significant content must survive export→import losslessly.
        let cards = [Card(term: "  spaced  ", definition: "trailing ")]
        let rows = CSVCodec.parse(CSVCodec.export(cards))
        #expect(rows.count == 1)
        #expect(rows[0].term == "  spaced  ")
        #expect(rows[0].definition == "trailing ")
    }

    @Test func trimsUnquotedFields() {
        // Hand-written CSV with spaces after the comma should still be trimmed.
        let rows = CSVCodec.parse("Term,Definition\nSprint, A time-box \n")
        #expect(rows[0] == CSVCodec.Row(term: "Sprint", definition: "A time-box"))
    }

    @Test func roundTrips() {
        let cards = [
            Card(term: "Sprint", definition: "A, time-box"),
            Card(term: "Scrum", definition: "Frame\"work"),
        ]
        let rows = CSVCodec.parse(CSVCodec.export(cards))
        #expect(rows == [
            CSVCodec.Row(term: "Sprint", definition: "A, time-box"),
            CSVCodec.Row(term: "Scrum", definition: "Frame\"work"),
        ])
    }

    @Test func roundTripsSectionColumn() {
        let cards = [
            Card(term: "correr", definition: "to run", section: "Verbs"),
            Card(term: "gato", definition: "cat", section: "Nouns"),
        ]
        let csv = CSVCodec.export(cards)
        #expect(csv.hasPrefix("Term,Definition,Section\n"))   // section column added when used
        #expect(CSVCodec.parse(csv) == [
            CSVCodec.Row(term: "correr", definition: "to run", section: "Verbs"),
            CSVCodec.Row(term: "gato", definition: "cat", section: "Nouns"),
        ])
    }

    @Test func sectionlessExportStaysTwoColumn() {
        let csv = CSVCodec.export([Card(term: "a", definition: "b")])
        #expect(csv.hasPrefix("Term,Definition\n"))
        #expect(!csv.contains("Section"))
    }

    // MARK: Insights export

    @Test func statsCSVHasSummaryDeckAndDailyBlocks() {
        var insights = StudyInsights()
        insights.currentStreak = 5
        insights.reviewsAllTime = 100
        insights.totalCards = 8
        insights.newCount = 1; insights.learningCount = 2; insights.matureCount = 5
        insights.dueNow = 2
        insights.perDeck = [.init(id: UUID(), name: "World, Capitals", colorHex: "#34C759",
                                  totalCards: 8, due: 2, newCount: 1, learningCount: 2, matureCount: 5)]
        let csv = StatsCSV.export(insights: insights, reviewsByDay: ["2026-06-01": 8], correctByDay: ["2026-06-01": 6])

        #expect(csv.contains("Metric,Value"))
        #expect(csv.contains("Current streak (days),5"))
        #expect(csv.contains("Deck,Cards,Due,New,Learning,Mature"))
        #expect(csv.contains("\"World, Capitals\",8,2,1,2,5"))   // comma in the name → quoted
        #expect(csv.contains("Date,Reviews,Correct"))
        #expect(csv.contains("2026-06-01,8,6"))
    }
}
