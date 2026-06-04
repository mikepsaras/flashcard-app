import SwiftUI

/// Bottom study controls — grading + undo. (Shuffle lives in the top toolbar.)
/// - Two-button: ✕ / ✓ icon pills centered, Undo bottom-left.
/// - Four-button: an Undo row above an Again/Hard/Good/Easy pill row.
struct StudyControlsBar: View {
    let canUndo: Bool
    var compact: Bool = false
    var fourButton: Bool = false
    var onUndo: () -> Void
    var onGrade: (Grade) -> Void

    var body: some View {
        if fourButton {
            VStack(spacing: 14) {
                HStack { undoButton; Spacer() }
                fourButtonRow
            }
        } else {
            ZStack {
                HStack(spacing: 16) {
                    gradePill("xmark", .again, "Don't know")
                    gradePill("checkmark", .good, "Know")
                }
                HStack { undoButton; Spacer() }
            }
        }
    }

    // MARK: Two-button — icon-only pills

    private func gradePill(_ symbol: String, _ grade: Grade, _ label: String) -> some View {
        let color = grade.studyColor
        return Button { onGrade(grade) } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 104, height: 54)
                .background(color.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .shadow(color: color.opacity(0.18), radius: 8, x: 0, y: 3)
        .accessibilityLabel(label)
    }

    // MARK: Four-button — labeled pills

    private var fourButtonRow: some View {
        HStack(spacing: 10) {
            gradeButton("Again", .again)
            gradeButton("Hard", .hard)
            gradeButton("Good", .good)
            gradeButton("Easy", .easy)
        }
    }

    private func gradeButton(_ title: String, _ grade: Grade) -> some View {
        let color = grade.studyColor
        return Button { onGrade(grade) } label: {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(color.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Undo

    private var undoButton: some View {
        Button(action: onUndo) {
            Group {
                if compact {
                    Image(systemName: "arrow.uturn.backward")
                } else {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .buttonStyle(.plain)
        .foregroundStyle(canUndo ? Color.secondary : Color.secondary.opacity(0.4))
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
    }
}

/// Canonical color for each grade, shared by the grading buttons and the progress bar
/// so a bar segment matches the button that produced it.
extension Grade {
    var studyColor: Color {
        switch self {
        case .again: Theme.danger
        case .hard:  Theme.learning
        case .good:  Theme.success
        case .easy:  Theme.accent
        }
    }
}

#Preview("Two-button") {
    StudyControlsBar(canUndo: true, onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}

#Preview("Four-button") {
    StudyControlsBar(canUndo: true, fourButton: true, onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}
