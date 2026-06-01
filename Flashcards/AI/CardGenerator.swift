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
        apiKey: String
    ) async throws -> [GeneratedCard] {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw AIError.missingKey }

        var request = Self.request(for: provider, prompt: prompt, count: count, model: model, apiKey: apiKey)
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
        guard !cards.isEmpty else { throw AIError.empty }
        return cards
    }

    static func request(for provider: AIProvider, prompt: String, count: Int?, model: String, apiKey: String) -> URLRequest {
        switch provider {
        case .openAI:    OpenAIProvider.makeRequest(prompt: prompt, count: count, model: model, apiKey: apiKey)
        case .google:    GeminiProvider.makeRequest(prompt: prompt, count: count, model: model, apiKey: apiKey)
        case .anthropic: AnthropicProvider.makeRequest(prompt: prompt, count: count, model: model, apiKey: apiKey)
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
}
