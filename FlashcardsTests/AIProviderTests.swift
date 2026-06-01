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

    @Test func geminiRequestPutsModelAndKeyInURL() {
        let req = GeminiProvider.makeRequest(prompt: "x", count: 5, model: "gemini-2.0-flash", apiKey: "AIza-test")
        let url = req.url?.absoluteString ?? ""
        #expect(url.contains("/models/gemini-2.0-flash:generateContent"))
        #expect(url.contains("key=AIza-test"))
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
}
