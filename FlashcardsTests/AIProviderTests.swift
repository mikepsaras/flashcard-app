import Testing
import Foundation
@testable import Flashcards

@Suite struct AIProviderTests {

    // MARK: Request building

    @Test func openAIRequestHasAuthAndJSONFormat() throws {
        let req = OpenAIProvider.makeRequest(prompt: "Spanish verbs", count: 8, model: "gpt-4o-mini", apiKey: "sk-test")
        #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "gpt-4o-mini")
        let format = body?["response_format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_object")
    }

    @Test func geminiRequestPutsModelInURLAndKeyInHeader() {
        let req = GeminiProvider.makeRequest(prompt: "x", count: 5, model: "gemini-2.0-flash", apiKey: "AIza-test")
        let url = req.url?.absoluteString ?? ""
        #expect(url.contains("/models/gemini-2.0-flash:generateContent"))
        #expect(!url.contains("AIza-test"))   // key must NOT leak into the URL
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
    }

    @Test func autoModeOmitsAnyCountInstruction() throws {
        let req = OpenAIProvider.makeRequest(prompt: "x", count: nil, model: "gpt-4o-mini", apiKey: "k")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        let system = (messages?.first?["content"] as? String ?? "")
        let user = (messages?.last?["content"] as? String ?? "")
        // Auto mode hints at no count anywhere — the model decides freely.
        #expect(!system.contains("exactly"))
        #expect(!system.contains("as many"))
        #expect(!system.contains("warrants"))
        #expect(!user.contains("appropriate number"))
    }

    @Test func explicitCountAsksForExactNumber() throws {
        let req = OpenAIProvider.makeRequest(prompt: "x", count: 8, model: "gpt-4o-mini", apiKey: "k")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        let system = (body?["messages"] as? [[String: Any]])?.first?["content"] as? String ?? ""
        #expect(system.contains("exactly 8"))
    }

    @Test func anthropicRequestHasVersionAndKeyHeaders() {
        let req = AnthropicProvider.makeRequest(prompt: "x", count: 5, model: "claude-3-5-haiku-latest", apiKey: "ak-test")
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "ak-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    // MARK: Response parsing

    @Test func parsesOpenAIEnvelope() throws {
        let content = #"{"cards":[{"term":"Sprint","definition":"A time-box"},{"term":"Scrum","definition":"A framework"}]}"#
        let payload = ["choices": [["message": ["content": content]]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let cards = try OpenAIProvider.parse(data)
        #expect(cards.count == 2)
        #expect(cards[0].term == "Sprint")
    }

    @Test func parsesGeminiEnvelope() throws {
        let text = #"{"cards":[{"term":"Japan","definition":"Tokyo"}]}"#
        let payload = ["candidates": [["content": ["parts": [["text": text]]]]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let cards = try GeminiProvider.parse(data)
        #expect(cards == [GeneratedCard(id: cards[0].id, term: "Japan", definition: "Tokyo")])
    }

    @Test func parsesAnthropicEnvelope() throws {
        let text = #"{"cards":[{"term":"Velocity","definition":"Work per sprint"}]}"#
        let payload = ["content": [["type": "text", "text": text]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let cards = try AnthropicProvider.parse(data)
        #expect(cards.first?.term == "Velocity")
    }

    // MARK: Tolerant JSON

    @Test func stripsMarkdownFences() throws {
        let fenced = "```json\n{\"cards\":[{\"term\":\"A\",\"definition\":\"B\"}]}\n```"
        let cards = try CardJSON.parseCards(from: fenced)
        #expect(cards == [GeneratedCard(id: cards[0].id, term: "A", definition: "B")])
    }

    @Test func ignoresSurroundingProse() throws {
        let messy = "Sure! Here are your cards:\n{\"cards\":[{\"term\":\"A\",\"definition\":\"B\"}]}\nHope that helps."
        let cards = try CardJSON.parseCards(from: messy)
        #expect(cards.count == 1)
    }

    @Test func ignoresProseWithStrayBraces() throws {
        // Prose containing its own braces must not break extraction.
        let messy = "Sure, I'll make {3} cards:\n{\"cards\":[{\"term\":\"A\",\"definition\":\"B\"}]}\nEnjoy!"
        let cards = try CardJSON.parseCards(from: messy)
        #expect(cards.count == 1)
        #expect(cards[0].term == "A")
    }

    @Test func parsesBareTopLevelArray() throws {
        // A provider that answers with a bare array (no {"cards":…} wrapper).
        let bare = "[{\"term\":\"A\",\"definition\":\"B\"},{\"term\":\"C\",\"definition\":\"D\"}]"
        let cards = try CardJSON.parseCards(from: bare)
        #expect(cards.count == 2)
        #expect(cards[1].term == "C")
    }

    @Test func ignoresBracesInsideStringValues() throws {
        // A definition that literally contains braces shouldn't confuse the scanner.
        let json = "{\"cards\":[{\"term\":\"Set\",\"definition\":\"Written as {1, 2, 3}\"}]}"
        let cards = try CardJSON.parseCards(from: json)
        #expect(cards.count == 1)
        #expect(cards[0].definition == "Written as {1, 2, 3}")
    }

    @Test func dropsEmptyTerms() throws {
        let json = #"{"cards":[{"term":"","definition":"x"},{"term":"Keep","definition":"y"}]}"#
        let cards = try CardJSON.parseCards(from: json)
        #expect(cards.count == 1)
        #expect(cards[0].term == "Keep")
    }

    @Test func throwsOnGarbage() {
        #expect(throws: AIError.self) { try CardJSON.parseCards(from: "no json here") }
    }

    @Test func errorMessageExtraction() {
        let data = #"{"error":{"message":"Invalid API key"}}"#.data(using: .utf8)!
        #expect(CardGenerator.errorMessage(from: data) == "Invalid API key")
    }

    @Test func emptyKeyThrowsMissingKey() async {
        await #expect(throws: AIError.missingKey) {
            _ = try await CardGenerator().generate(prompt: "x", count: 5, provider: .openAI, model: "m", apiKey: "  ")
        }
    }

    // MARK: Prompt — formatting policy

    @Test func systemPromptAllowsMarkdownAndLatex() {
        let system = CardJSON.system(count: nil)
        #expect(system.contains("Markdown"))
        #expect(system.contains("LaTeX"))
        #expect(system.contains("$$"))   // the display-math delimiter is advertised
        // …but the JSON envelope itself must still be unwrapped (no fences around the reply).
        #expect(system.lowercased().contains("code fences"))
    }

    // MARK: Keychain (API-key storage)

    @Test func keychainRoundTrips() {
        let account = "apiKey.test.\(UUID().uuidString)"
        KeychainStore.set("sk-test-123", account: account)
        #expect(KeychainStore.get(account: account) == "sk-test-123")   // fails ⇒ keychain write isn't persisting
        KeychainStore.delete(account: account)
        #expect(KeychainStore.get(account: account) == nil)
    }

    // MARK: Understanding intent + elaboration (B2)

    @Test func parsesExtraElaboration() throws {
        let json = #"{"cards":[{"term":"Why does ice float?","definition":"It's less dense than water.","extra":"Hydrogen bonds lock water into an open lattice when it freezes, so the same mass takes up more volume."}]}"#
        let cards = try CardJSON.parseCards(from: json)
        #expect(cards.count == 1)
        #expect(cards[0].extra.contains("Hydrogen bonds"))
    }

    @Test func parsesExtraSynonymKey() throws {
        // "explanation" is an accepted alias for the elaboration.
        let cards = try CardJSON.parseCards(from: #"[{"term":"A","definition":"B","explanation":"because"}]"#)
        #expect(cards.first?.extra == "because")
    }

    @Test func recallCardsHaveEmptyExtra() throws {
        let cards = try CardJSON.parseCards(from: #"{"cards":[{"term":"A","definition":"B"}]}"#)
        #expect(cards.first?.extra == "")
    }

    @Test func understandingPromptAsksForReasoningAndExtra() {
        let system = CardJSON.system(count: nil, intent: .understanding)
        #expect(system.contains("\"extra\""))
        #expect(system.lowercased().contains("understanding"))
        #expect(!system.contains("minimum-information principle"))   // not the recall prompt
    }

    @Test func recallIsTheDefaultIntent() {
        // Existing callers (system(count:)) get the classic recall prompt unchanged.
        #expect(CardJSON.system(count: nil) == CardJSON.system(count: nil, intent: .recall))
        #expect(CardJSON.system(count: nil).contains("minimum-information principle"))
    }

    // MARK: Key tolerance (front/back, question/answer, case-insensitive)

    @Test func parsesFrontBackAndQuestionAnswerKeys() throws {
        let json = #"{"cards":[{"front":"A","back":"B"},{"question":"Q","answer":"C"}]}"#
        let cards = try CardJSON.parseCards(from: json)
        #expect(cards.count == 2)
        #expect(cards[0].term == "A" && cards[0].definition == "B")
        #expect(cards[1].term == "Q" && cards[1].definition == "C")
    }

    @Test func cardKeysAreCaseInsensitive() throws {
        let cards = try CardJSON.parseCards(from: #"[{"Term":"A","DEFINITION":"B"}]"#)
        #expect(cards.first?.term == "A")
        #expect(cards.first?.definition == "B")
    }

    @Test func mixedSynonymKeysWithSectionParse() throws {
        // q/a shorthand + a "category" alias for the section.
        let cards = try CardJSON.parseCards(from: #"{"cards":[{"q":"hola","a":"hello","category":"Greetings"}]}"#)
        #expect(cards.first?.term == "hola")
        #expect(cards.first?.definition == "hello")
        #expect(cards.first?.section == "Greetings")
    }

    // MARK: De-duplication (deck expansion)

    @Test func removingDuplicatesDropsExistingTerms() {
        let existing = [GeneratedCard(term: "Sprint", definition: "x")]
        let generated = [
            GeneratedCard(term: "sprint", definition: "dup — case-insensitive"),
            GeneratedCard(term: "Velocity", definition: "new"),
        ]
        #expect(CardGenerator.removingDuplicates(generated, of: existing).map(\.term) == ["Velocity"])
    }

    @Test func removingDuplicatesDropsWithinBatchRepeats() {
        let generated = [
            GeneratedCard(term: "A", definition: "1"),
            GeneratedCard(term: " a ", definition: "2"),   // same term, trimmed + cased
            GeneratedCard(term: "B", definition: "3"),
        ]
        #expect(CardGenerator.removingDuplicates(generated, of: []).map(\.term) == ["A", "B"])
    }

    @Test func removingDuplicatesKeepsAllWhenNoOverlap() {
        let generated = [GeneratedCard(term: "A", definition: "1"), GeneratedCard(term: "B", definition: "2")]
        #expect(CardGenerator.removingDuplicates(generated, of: [GeneratedCard(term: "C", definition: "3")]).count == 2)
    }

    // MARK: Card quality linter (S0.4)

    @Test func linterFlagsCircularEnumerationAndShortCards() {
        let cards = [
            GeneratedCard(term: "What is the powerhouse of the cell?", definition: "The mitochondrion"),
            GeneratedCard(term: "Photosynthesis", definition: "Photosynthesis is the process plants use."),
            GeneratedCard(term: "List the noble gases", definition: "- Helium\n- Neon\n- Argon\n- Krypton"),
            GeneratedCard(term: "Define entropy", definition: ""),
        ]
        let w = CardQualityLinter.warnings(for: cards)
        #expect(w[cards[0].id] == nil)                                  // a clean atomic card
        #expect(w[cards[1].id]?.contains(.circular) == true)
        #expect(w[cards[2].id]?.contains(.enumeration) == true)
        #expect(w[cards[3].id]?.contains(.shortAnswer) == true)
    }

    @Test func linterFlagsNearDuplicateTermsAcrossPunctuation() {
        let cards = [
            GeneratedCard(term: "What is HTTP?", definition: "A protocol"),
            GeneratedCard(term: "what is http", definition: "Hypertext transfer protocol"),
        ]
        let w = CardQualityLinter.warnings(for: cards)
        #expect(w[cards[0].id]?.contains(.duplicate) == true)
        #expect(w[cards[1].id]?.contains(.duplicate) == true)
    }

    @Test func linterPassesCleanAtomicCards() {
        let cards = [
            GeneratedCard(term: "Capital of France?", definition: "Paris"),
            GeneratedCard(term: "Capital of Japan?", definition: "Tokyo"),
        ]
        #expect(CardQualityLinter.warnings(for: cards).isEmpty)
    }

    @Test func linterDoesNotFlagAcronymInItsOwnExpansion() {
        // "HTML — HyperText Markup Language" is a good card, not circular.
        let cards = [GeneratedCard(term: "HTML", definition: "HyperText Markup Language (HTML)")]
        #expect(CardQualityLinter.warnings(for: cards)[cards[0].id]?.contains(.circular) != true)
    }

    @Test func linterDoesNotFlagTermInsideALongerWordAsCircular() {
        // "state" must not match "statement" — whole-token, not raw substring.
        let cards = [GeneratedCard(term: "State", definition: "A statement of intent.")]
        #expect(CardQualityLinter.warnings(for: cards)[cards[0].id]?.contains(.circular) != true)
    }

    @Test func linterFlagsMultiDigitNumberedLists() {
        // All two-digit markers — the old first-two-characters check counted none of these.
        let cards = [GeneratedCard(term: "Noble gases", definition: "10. Neon\n11. Sodium\n12. Argon")]
        #expect(CardQualityLinter.warnings(for: cards)[cards[0].id]?.contains(.enumeration) == true)
    }
}
