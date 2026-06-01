import SwiftUI

/// A text field whose placeholder disappears as soon as the field is focused
/// (not only once text has been typed). Font and other styling applied at the
/// call site propagate to the inner field via the environment.
struct ClearableTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int>? = nil

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let lines {
                TextField(focused ? "" : placeholder, text: $text, axis: axis)
                    .lineLimit(lines)
            } else {
                TextField(focused ? "" : placeholder, text: $text, axis: axis)
            }
        }
        .focused($focused)
    }
}
