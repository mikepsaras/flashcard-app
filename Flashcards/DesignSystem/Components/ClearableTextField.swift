import SwiftUI

/// A form text field with **native placeholder behavior**: the placeholder stays
/// visible until you start typing (it does *not* clear on focus), matching the system
/// text fields in Apple's own apps. A thin wrapper over `TextField` so call sites share
/// one placeholder + optional multiline line-limit; styling (font, etc.) applied at the
/// call site propagates to the inner field via the environment.
struct ClearableTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int>? = nil

    var body: some View {
        if let lines {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(lines)
        } else {
            TextField(placeholder, text: $text, axis: axis)
        }
    }
}
