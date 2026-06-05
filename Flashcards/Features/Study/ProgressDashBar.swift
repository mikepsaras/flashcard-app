import SwiftUI

/// Study progress. Up to 100 cards: one dash per card, tinted by the grade it got (✕ red, Hard
/// orange, ✓ green, Easy blue). Beyond 100 cards a dash each would be unreadably thin, so it becomes
/// a single % completion bar — green when most answered cards were correct, red when most were wrong.
struct ProgressDashBar: View {
    /// The grade given to each answered card, in order. Its length is how many are answered.
    let grades: [Grade]
    let total: Int
    var unfilled: Color = Color.primary.opacity(0.12)

    /// One dash per card up to here; beyond it, switch to the % completion bar.
    private let maxDashes = 100

    var body: some View {
        Group {
            if total > maxDashes {
                percentBar
            } else {
                dashes
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: grades.count)
        // The "N of M · C correct" subtitle carries this for VoiceOver, so the bar is decorative.
        .accessibilityHidden(true)
    }

    private var dashes: some View {
        let count = max(total, 1)
        // Tighten the gap as the count climbs so up to 100 dashes still fit one row.
        let spacing: CGFloat = count > 50 ? 2 : (count > 25 ? 3 : 5)
        return HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i < grades.count ? grades[i].studyColor : unfilled)
                    .frame(height: 6)
            }
        }
    }

    /// >100 cards: a continuous completion bar (fill = answered / total), tinted by whether the
    /// answered cards are mostly correct (green) or mostly wrong (red).
    private var percentBar: some View {
        let answered = grades.count
        let fraction = total > 0 ? min(Double(answered) / Double(total), 1) : 0
        let correct = grades.filter(\.isCorrect).count
        let fill: Color = answered == 0 ? unfilled : (correct * 2 >= answered ? Theme.success : Theme.danger)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(unfilled)
                Capsule().fill(fill).frame(width: max(geo.size.width * fraction, fraction > 0 ? 8 : 0))
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressDashBar(grades: [.good, .good, .again, .good], total: 12)                          // dashes, one per card
        ProgressDashBar(grades: Array(repeating: .good, count: 80) + [.again, .again], total: 150) // % bar (mostly correct → green)
    }
    .padding()
}
