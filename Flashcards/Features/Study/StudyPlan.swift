import SwiftUI

/// Describes a study run independently of where the cards come from (a single
/// deck, or the cross-deck "Today" queue). `makeCards` is evaluated when the
/// session starts and on "Study Again", so it always reflects current due state.
struct StudyPlan: Identifiable {
    let id: String
    let title: String
    let accent: Color
    /// Text shared via the share button; `nil` hides the button (e.g. Today).
    let exportText: String?
    let makeCards: () -> [Card]
}
