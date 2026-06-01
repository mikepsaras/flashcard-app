import Testing
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

    @Test func exportEscapesSpecialCharacters() {
        let csv = CSVCodec.export([Card(term: "a,b", definition: "quote\"x")])
        #expect(csv.contains("\"a,b\""))
        #expect(csv.contains("\"quote\"\"x\""))
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
}
