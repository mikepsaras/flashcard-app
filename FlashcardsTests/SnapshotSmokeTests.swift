import Testing
import SwiftUI
@testable import Flashcards

#if os(macOS)
@Suite(.serialized)
struct SnapshotSmokeTests {
    @MainActor
    @Test func renderPipelineProducesPNG() throws {
        let view = ZStack {
            Color.white
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.95, green: 0.96, blue: 0.98))
                .padding(40)
            Text("User Stories")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
        }

        try Snapshot.write(view, size: CGSize(width: 640, height: 640), name: "00_smoke")
        #expect(FileManager.default.fileExists(atPath: "\(Snapshot.directory)/00_smoke.png"))
    }
}
#endif
