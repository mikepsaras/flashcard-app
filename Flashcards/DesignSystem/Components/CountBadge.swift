import SwiftUI

/// The red ✕ / green ✓ tally pills shown while studying.
struct CountBadge: View {
    enum Kind { case correct, wrong }

    let kind: Kind
    let count: Int

    private var color: Color { kind == .correct ? Theme.success : Theme.danger }
    private var symbol: String { kind == .correct ? "checkmark" : "xmark" }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text("\(count)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
    }
}

#Preview {
    HStack { CountBadge(kind: .wrong, count: 1); CountBadge(kind: .correct, count: 4) }
        .padding()
}
