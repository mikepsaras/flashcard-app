import Foundation

/// OpenAI Chat Completions with JSON response format.
enum OpenAIProvider {
    static func makeRequest(prompt: String, count: Int?, model: String, apiKey: String, existing: [GeneratedCard] = [], intent: GenerationIntent = .recall) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": CardJSON.system(count: count, expanding: !existing.isEmpty, intent: intent)],
                ["role": "user", "content": CardJSON.user(prompt, count: count, existing: existing)],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(_ data: Data) throws -> [GeneratedCard] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIError.decoding }
        return try CardJSON.parseCards(from: content)
    }
}
