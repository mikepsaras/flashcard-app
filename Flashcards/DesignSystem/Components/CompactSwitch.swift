import SwiftUI

/// A small custom switch that looks and behaves identically on macOS and iOS
/// (the native `.switch` toggle diverges between platforms). Matches the clean
/// iOS-style switch in the reference design.
struct CompactSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = Theme.accent

    private let width: CGFloat = 46
    private let height: CGFloat = 28

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? tint : Color.primary.opacity(0.20))
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                .padding(2.5)
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { isOn.toggle() }
        .accessibilityElement()
        .accessibilityLabel("Toggle")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 16) {
        CompactSwitch(isOn: .constant(true))
        CompactSwitch(isOn: .constant(false))
    }
    .padding()
}
