import SwiftUI

/// Bottom study controls.
/// - Two-button: Undo (left), ✕/✓ centered, Track learning (right) — one row.
/// - Four-button: a utility row (Undo + Track learning) above an Again/Hard/Good/Easy row.
struct StudyControlsBar: View {
    let canUndo: Bool
    var compact: Bool = false
    var fourButton: Bool = false
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
                CircleIconButton(systemName: "xmark", tint: Theme.danger, size: 60, weight: .bold) { onGrade(.again) }
                CircleIconButton(systemName: "checkmark", tint: Theme.success, size: 60, weight: .bold) { onGrade(.good) }
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
            gradeButton("Again", .again, Theme.danger)
            gradeButton("Hard", .hard, Color(hex: "#FF9500"))
            gradeButton("Good", .good, Theme.success)
            gradeButton("Easy", .easy, Theme.accent)
        }
    }

    private func gradeButton(_ title: String, _ grade: Grade, _ color: Color) -> some View {
        Button { onGrade(grade) } label: {
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

    private func trackToggle(showLabel: Bool) -> some View {
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

#Preview("Two-button") {
    StudyControlsBar(canUndo: true, trackLearning: .constant(true), onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}

#Preview("Four-button") {
    StudyControlsBar(canUndo: true, fourButton: true, trackLearning: .constant(true), onUndo: {}, onGrade: { _ in })
        .padding().frame(width: 560)
}
