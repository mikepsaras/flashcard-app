import Foundation

/// Google Gemini generateContent with JSON response MIME type.
enum GeminiProvider {
    static func makeRequest(prompt: String, count: Int?, model: String, apiKey: String) -> URLRequest {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Pass the key as a header rather than a URL query param: query strings leak
        // into logs/proxies/crash reports far more readily than headers do.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [["parts": [["text": CardJSON.combined(prompt, count: count)]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.4,
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(_ data: Data) throws -> [GeneratedCard] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = object["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else { throw AIError.decoding }
        return try CardJSON.parseCards(from: text)
    }
}
