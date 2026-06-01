import Foundation

enum AIError: LocalizedError, Equatable {
    case missingKey
    case http(Int, String)
    case decoding
    case empty
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "No API key set. Add one in Settings → AI."
        case .http(let code, let message):
            "Request failed (\(code)). \(message)"
        case .decoding:
            "Couldn't read the AI response. Try again."
        case .empty:
            "The AI didn't return any cards. Try rephrasing your notes."
        case .network(let message):
            "Network error: \(message)"
        }
    }
}
