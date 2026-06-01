import SwiftUI

/// Bottom controls: Undo (left), ✕/✓ (centered), Track learning toggle (right).
/// In `compact` width the text labels collapse so the centered grade buttons
/// never collide with the edge controls.
struct StudyControlsBar: View {
    let canUndo: Bool
    var compact: Bool = false
    @Binding var trackLearning: Bool
    var onUndo: () -> Void
    var onWrong: () -> Void
    var onCorrect: () -> Void

    var body: some View {
        ZStack {
            // Centered grade buttons.
            HStack(spacing: 22) {
                CircleIconButton(systemName: "xmark", tint: Theme.danger, size: 60, weight: .bold, action: onWrong)
                CircleIconButton(systemName: "checkmark", tint: Theme.success, size: 60, weight: .bold, action: onCorrect)
            }

            // Edge controls overlaid so the grade buttons stay perfectly centered.
            HStack(spacing: 12) {
                undoButton
                Spacer(minLength: 8)
                trackToggle
            }
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Group {
                if compact {
                    Image(systemName: "arrow.uturn.backward")
                } else {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
            }
            .font(Typography.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(canUndo ? Color.primary : Color.secondary.opacity(0.45))
        .disabled(!canUndo)
        .accessibilityLabel("Undo")
    }

    private var trackToggle: some View {
        HStack(spacing: 8) {
            if !compact {
                Text("Track learning").font(Typography.callout)
            }
            CompactSwitch(isOn: $trackLearning)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Track learning")
        .accessibilityValue(trackLearning ? "On" : "Off")
    }
}

#Preview("Regular") {
    StudyControlsBar(canUndo: true, compact: false, trackLearning: .constant(true), onUndo: {}, onWrong: {}, onCorrect: {})
        .padding().frame(width: 560)
}

#Preview("Compact") {
    StudyControlsBar(canUndo: true, compact: true, trackLearning: .constant(true), onUndo: {}, onWrong: {}, onCorrect: {})
        .padding().frame(width: 380)
}
