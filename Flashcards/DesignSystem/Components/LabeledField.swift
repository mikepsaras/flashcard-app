import SwiftUI

/// A labeled editor field: a small caption above the field, with the text sitting in a
/// clean rounded box (a step lighter than the page). The placeholder is native — it stays
/// visible until you type. Supports a multi-line box via `lines` (a tidy text area).
struct LabeledField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            field
                .textFieldStyle(.plain)
                .font(Typography.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.fieldSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
        }
    }

    @ViewBuilder private var field: some View {
        if let lines {
            TextField(placeholder, text: $text, axis: axis).lineLimit(lines)
        } else {
            TextField(placeholder, text: $text, axis: axis)
        }
    }
}

#Preview {
    VStack(spacing: 22) {
        LabeledField(label: "Name", placeholder: "Deck name", text: .constant(""))
        LabeledField(label: "Definition", placeholder: "Back of the card", text: .constant(""), axis: .vertical, lines: 3...10)
    }
    .padding(24)
    .frame(width: 380)
    .background(Theme.groupedBackground)
}
