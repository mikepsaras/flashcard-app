import SwiftUI

/// Bottom study controls.
/// - Two-button: Undo (left), ✕/✓ centered, Track learning (right) — one row.
/// - Four-button: a utility row (Undo + Track learning) above an Again/Hard/Good/Easy row.
struct StudyControlsBar: View {
    let canUndo: Bool
    var compact: Bool = false
    var fourButton: Bool = false
    var isPractice: Bool = false
    @Binding var trackLearning: Bool
    var onUndo: () -> Void
    var onGrade: (Grade) -> Void

    var body: some View {
        if fourButton {
            VStack(spacing: 16) {
                utilityRow
                fourButtonRow
            }
        } else {
            twoButtonBar
        }
    }

    // MARK: Two-button

    private var twoButtonBar: some View {
        ZStack {
            HStack(spacing: 22) {
                CircleIconButton(systemName: "xmark", tint: Grade.again.studyColor, size: 60, weight: .bold) { onGrade(.again) }
                CircleIconButton(systemName: "checkmark", tint: Grade.good.studyColor, size: 60, weight: .bold) { onGrade(.good) }
            }
            HStack(spacing: 12) {
                undoButton(showLabel: !compact)
                Spacer(minLength: 8)
                trackToggle(showLabel: !compact)
            }
        }
    }

    // MARK: Four-button

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
        }
        .buttonStyle(.plain)
    }

    private var utilityRow: some View {
        HStack(spacing: 12) {
            undoButton(showLabel: true)
            Spacer(minLength: 8)
            trackToggle(showLabel: true)
        }
    }

    // MARK: Shared pieces

    private func undoButton(showLabel: Bool) -> some View {
        Button(action: onUndo) {
            Group {
                if showLabel {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                } else {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .font(Typography.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(canUndo ? Color.primary : Color.secondary.opacity(0.45))
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
    }

    @ViewBuilder private func trackToggle(showLabel: Bool) -> some View {
        if isPractice {
            // Nothing is due — schedules won't change, so the toggle is moot. Show why.
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                if showLabel { Text("Practice") }
            }
            .font(Typography.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Practice mode")
            .accessibilityHint("Nothing is due, so your review schedule won't change")
        } else {
            HStack(spacing: 8) {
                if showLabel {
                    Text("Track learning").font(Typography.callout)
                }
                CompactSwitch(isOn: $trackLearning)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Track learning")
            .accessibilityValue(trackLearning ? "On" : "Off")
        }
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
    StudyControlsBar(canUndo: true, trackLearning: .constant(true), onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}

#Preview("Four-button") {
    StudyControlsBar(canUndo: true, fourButton: true, trackLearning: .constant(true), onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}
