import Foundation

/// Google Gemini generateContent with JSON response MIME type.
enum GeminiProvider {
    static func makeRequest(prompt: String, count: Int?, model: String, apiKey: String) -> URLRequest {
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? apiKey
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(encodedKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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

extension CharacterSet {
    /// Query-value safe set (excludes `&`, `=`, `+`, etc.).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?/")
        return set
    }()
}
