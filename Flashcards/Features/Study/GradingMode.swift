import Foundation

/// How the study controls present grading. Persisted in `@AppStorage`.
enum GradingMode: String, CaseIterable, Identifiable {
    case twoButton    // ✕ / ✓  → again / good
    case fourButton   // Again / Hard / Good / Easy

    var id: String { rawValue }

    static let storageKey = "gradingMode"

    var title: String {
        switch self {
        case .twoButton:  "Know / Don't know"
        case .fourButton: "Again / Hard / Good / Easy"
        }
    }
}
