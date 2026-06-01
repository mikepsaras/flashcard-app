import SwiftUI

/// A round icon button — used for the ✕/✓ study controls and header actions.
struct CircleIconButton: View {
    let systemName: String
    var tint: Color = Theme.accent
    var fill: Color? = nil
    var size: CGFloat = 56
    var weight: Font.Weight = .semibold
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: weight))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(fill ?? tint.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 20) {
        CircleIconButton(systemName: "xmark", tint: Theme.danger) {}
        CircleIconButton(systemName: "checkmark", tint: Theme.success) {}
    }
    .padding()
}
