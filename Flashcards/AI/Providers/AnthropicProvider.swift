import Foundation

/// Anthropic Messages API. No JSON mode — relies on the prompt + tolerant parser.
enum AnthropicProvider {
    static func makeRequest(prompt: String, count: Int, model: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": CardJSON.system(count: count),
            "messages": [["role": "user", "content": CardJSON.user(prompt, count: count)]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(_ data: Data) throws -> [GeneratedCard] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = object["content"] as? [[String: Any]]
        else { throw AIError.decoding }

        let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
            ?? content.first?["text"] as? String
        guard let text else { throw AIError.decoding }
        return try CardJSON.parseCards(from: text)
    }
}
