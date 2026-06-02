import SwiftUI

/// Describes a study run independently of where the items come from (a single deck, or
/// the cross-deck "Today" queue). `makeItems` is evaluated when the session starts and
/// on "Study Again", so it always reflects current due state.
struct StudyPlan: Identifiable {
    let id: String
    let title: String
    let accent: Color
    /// Text shared via the share button; `nil` hides the button (e.g. Today).
    let exportText: String?
    /// Whether this run uses 4-button grading. Set from the deck's own setting; the
    /// cross-deck Today queue uses 2-button.
    let fourButton: Bool
    let makeItems: () -> [ReviewItem]
}
