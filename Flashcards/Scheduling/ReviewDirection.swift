import Foundation

/// Which way a card is being studied. With reverse study enabled, a card is scheduled
/// independently in each direction.
enum ReviewDirection: String, Codable, Sendable, CaseIterable {
    case forward   // prompt with the term, answer with the definition
    case reverse   // prompt with the definition, answer with the term
}
