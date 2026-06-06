import Foundation

/// Calls the selected provider and returns suggested cards. Pure async; safe to
/// call from the main actor (the network work suspends off-main).
struct CardGenerator: Sendable {
    var session: URLSession = .shared

    func generate(
        prompt: String,
        count: Int?,
        provider: AIProvider,
        model: String,
        apiKey: String,
        existing: [GeneratedCard] = [],
        intent: GenerationIntent = .recall
    ) async throws -> [GeneratedCard] {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingKey }

        var request = Self.request(for: provider, prompt: prompt, count: count, model: model, apiKey: apiKey, existing: existing, intent: intent)
        // Don't let a hung connection spin the "Generating…" UI for the default 60s.
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, Self.errorMessage(from: data))
        }

        let cards = try Self.parse(provider: provider, data: data)
        // Drop any card that duplicates an existing deck term (when expanding) or repeats within
        // the batch, so the review list never offers a card the deck already has.
        let deduped = Self.removingDuplicates(cards, of: existing)
        guard !deduped.isEmpty else { throw AIError.empty }
        return deduped
    }

    static func request(for provider: AIProvider, prompt: String, count: Int?, model: String, apiKey: String, existing: [GeneratedCard] = [], intent: GenerationIntent = .recall) -> URLRequest {
        switch provider {
        case .openAI:    OpenAIProvider.makeRequest(prompt: prompt, count: count, model: model, apiKey: apiKey, existing: existing, intent: intent)
        case .google:    GeminiProvider.makeRequest(prompt: prompt, count: count, model: model, apiKey: apiKey, existing: existing, intent: intent)
        case .anthropic: AnthropicProvider.makeRequest(prompt: prompt, count: count, model: model, apiKey: apiKey, existing: existing, intent: intent)
        }
    }

    static func parse(provider: AIProvider, data: Data) throws -> [GeneratedCard] {
        switch provider {
        case .openAI:    try OpenAIProvider.parse(data)
        case .google:    try GeminiProvider.parse(data)
        case .anthropic: try AnthropicProvider.parse(data)
        }
    }

    /// Best-effort extraction of a provider error message for display.
    static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = object["error"] as? String { return message }
        }
        return String(data: data.prefix(200), encoding: .utf8) ?? "Unknown error"
    }

    /// Removes cards whose term duplicates an existing deck term, or repeats an earlier card in
    /// the batch (case-insensitive). Pure + static so it's unit-testable.
    static func removingDuplicates(_ cards: [GeneratedCard], of existing: [GeneratedCard]) -> [GeneratedCard] {
        func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let existingTerms = Set(existing.map { key($0.term) })
        var seen = Set<String>()
        var out: [GeneratedCard] = []
        for card in cards {
            let k = key(card.term)
            guard !existingTerms.contains(k), !seen.contains(k) else { continue }
            seen.insert(k)
            out.append(card)
        }
        return out
    }
}
