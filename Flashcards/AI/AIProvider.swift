import Foundation

/// Supported AI providers for card generation. Keys live in the Keychain; the
/// selected provider and per-provider model live in `@AppStorage`.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case google
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:    "OpenAI"
        case .google:    "Google Gemini"
        case .anthropic: "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:    "gpt-4.1-mini"
        case .google:    "gemini-2.5-flash"
        case .anthropic: "claude-haiku-4-5"
        }
    }

    /// Where the user gets an API key (shown as help text).
    var keyConsoleURL: String {
        switch self {
        case .openAI:    "platform.openai.com/api-keys"
        case .google:    "aistudio.google.com/app/apikey"
        case .anthropic: "console.anthropic.com/settings/keys"
        }
    }

    var keychainAccount: String { "apiKey.\(rawValue)" }
    var modelDefaultsKey: String { "aiModel.\(rawValue)" }

    static let selectedProviderKey = "aiSelectedProvider"
}
