import SwiftUI

/// Bottom study controls — an Undo row above the grade pills (Again / Good / Easy, the 1.8.0 3-button
/// set). (Shuffle / Share / Reset live in the study screen's ••• menu now.) When `intervalFor` is
/// supplied (a developer toggle), each pill shows the projected next interval beneath its label.
struct StudyControlsBar: View {
    let canUndo: Bool
    var compact: Bool = false
    /// Developer diagnostic: the projected next interval for a grade, shown under its label. Hidden
    /// by default so the numbers don't bias honest grading.
    var intervalFor: ((Grade) -> String)? = nil
    var onUndo: () -> Void
    var onGrade: (Grade) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack { undoButton; Spacer() }
            HStack(spacing: 10) {
                gradeButton("Again", .again)
                gradeButton("Good", .good)
                gradeButton("Easy", .easy)
            }
        }
    }

    /// One full-width grade pill (Again / Good / Easy, all label-only). A projected-interval subtitle
    /// appears beneath when `intervalFor` is set.
    private func gradeButton(_ title: String, _ grade: Grade) -> some View {
        let color = grade.studyColor
        return Button { onGrade(grade) } label: {
            VStack(spacing: 3) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
                if let intervalFor {
                    Text(intervalFor(grade))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, intervalFor == nil ? 13 : 11)
            .background(color.opacity(Theme.Opacity.fillTint), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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

#Preview("Grade bar") {
    StudyControlsBar(canUndo: true, onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}
