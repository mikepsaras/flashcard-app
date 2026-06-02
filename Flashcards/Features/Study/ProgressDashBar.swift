import SwiftUI

/// Segmented dash progress — one capsule per card, each answered card tinted with the
/// color of the grade it was given (✕ red, ✓ green, Hard orange, Easy blue). Sessions
/// larger than `maxSegments` compress into buckets.
struct ProgressDashBar: View {
    /// Grade color for each answered card, in order; its count is how many are answered.
    let colors: [Color]
    let total: Int
    var unfilled: Color = Color.primary.opacity(0.12)

    /// Cap the number of rendered segments so very large decks stay tidy.
    private let maxSegments = 30

    private var segments: Int { max(min(total, maxSegments), 1) }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<segments, id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(height: 5)
            }
        }
        .animation(.snappy, value: colors.count)
    }

    /// One-to-one with cards when the session fits; otherwise each segment spans a
    /// bucket of cards and shows the most recent answered card's color in that bucket.
    private func color(for i: Int) -> Color {
        guard total > 0 else { return unfilled }
        if total <= maxSegments {
            return i < colors.count ? colors[i] : unfilled
        }
        let bucketStart = i * total / segments
        let bucketEnd = (i + 1) * total / segments          // exclusive
        let lastAnswered = min(colors.count, bucketEnd) - 1
        return lastAnswered >= bucketStart ? colors[lastAnswered] : unfilled
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressDashBar(colors: [.green, .green, .red, .green], total: 12)
        ProgressDashBar(colors: [.green, .red], total: 5)
    }
    .padding()
}
