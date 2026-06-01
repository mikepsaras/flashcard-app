import SwiftUI

/// Segmented dash progress — one capsule per card, filled as you advance.
struct ProgressDashBar: View {
    let answered: Int
    let total: Int
    var accent: Color = Theme.accent

    /// Cap the number of rendered segments so very large decks stay tidy.
    private let maxSegments = 30

    private var segments: Int { max(min(total, maxSegments), 1) }
    private var filledSegments: Int {
        guard total > 0 else { return 0 }
        return Int((Double(answered) / Double(total) * Double(segments)).rounded())
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<segments, id: \.self) { i in
                Capsule()
                    .fill(i < filledSegments ? accent : Color.primary.opacity(0.12))
                    .frame(height: 5)
            }
        }
        .animation(.snappy, value: filledSegments)
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressDashBar(answered: 6, total: 25)
        ProgressDashBar(answered: 2, total: 5)
    }
    .padding()
}
