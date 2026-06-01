import SwiftUI

/// A prominent filled capsule button (e.g. "Study").
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PrimaryButton(title: "Study", systemImage: "play.fill") {}
        .padding()
}
