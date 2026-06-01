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
}
