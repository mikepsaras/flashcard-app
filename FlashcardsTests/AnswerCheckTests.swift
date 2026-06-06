import Testing
@testable import Flashcards

/// The type-in answer comparator (B3): forgiving about case + whitespace, strict about meaning.
@Suite struct AnswerCheckTests {
    @Test func caseInsensitive() {
        #expect(AnswerCheck.matches("Mitochondria", "mitochondria"))
        #expect(AnswerCheck.matches("PARIS", "paris"))
    }

    @Test func whitespaceForgiving() {
        #expect(AnswerCheck.matches("  to   run ", "to run"))
        #expect(AnswerCheck.matches("to\nrun", "to run"))
    }

    @Test func trailingPeriodIgnored() {
        #expect(AnswerCheck.matches("to run.", "to run"))
        #expect(AnswerCheck.matches("Paris", "Paris."))
    }

    @Test func rejectsWrongAnswers() {
        #expect(!AnswerCheck.matches("mitochondrion", "mitochondria"))
        #expect(!AnswerCheck.matches("London", "Paris"))
    }

    @Test func blankNeverMatches() {
        #expect(!AnswerCheck.matches("", "anything"))
        #expect(!AnswerCheck.matches("    ", "anything"))
        #expect(!AnswerCheck.matches("\n", ""))
    }

    @Test func accentsAreSignificant() {
        // Accents carry meaning (el vs él), so they're not folded away.
        #expect(!AnswerCheck.matches("el", "él"))
        #expect(AnswerCheck.matches("Él", "él"))
    }

    @Test func normalizeCollapsesWhitespaceAndCase() {
        #expect(AnswerCheck.normalize("  A\n B ") == "a b")
        #expect(AnswerCheck.normalize("Hello.") == "hello")
    }
}
