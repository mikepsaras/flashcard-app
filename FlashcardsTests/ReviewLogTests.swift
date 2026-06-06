import Testing
import Foundation
@testable import Flashcards

@Suite struct ReviewLogTests {

    /// Runs `body` with a throwaway log file in a temp dir, cleaned up after — never the real library.
    private func withTempLog(_ body: (URL) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rl-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ReviewLog.fileURL(in: dir))
    }

    private func record(correct: Bool = true) -> ReviewLog.Record {
        ReviewLog.Record(ts: Date(timeIntervalSince1970: 1_700_000_000), deck: UUID(), card: UUID(),
                         direction: .forward, grade: correct ? 4 : 0, correct: correct,
                         elapsedDays: 3, intervalBefore: 6, mature: false)
    }

    @Test func appendThenReadRoundTrips() {
        withTempLog { url in
            let a = record(correct: true), b = record(correct: false)
            ReviewLog.append(a, to: url)
            ReviewLog.append(b, to: url)
            let out = ReviewLog.records(from: url)
            #expect(out == [a, b])               // order + every field preserved
            #expect(out[0].direction == .forward)
        }
    }

    @Test func voidDropsTheRecord() {
        withTempLog { url in
            let a = record(), b = record()
            ReviewLog.append(a, to: url)
            ReviewLog.append(b, to: url)
            ReviewLog.void(b.id, to: url)
            #expect(ReviewLog.records(from: url).map(\.id) == [a.id])   // b voided, a kept
        }
    }

    @Test func corruptLinesAreSkipped() {
        withTempLog { url in
            let a = record()
            ReviewLog.append(a, to: url)
            if let handle = try? FileHandle(forWritingTo: url) {       // append junk + a blank line
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("not json\n\n".utf8))
                try? handle.close()
            }
            #expect(ReviewLog.records(from: url).map(\.id) == [a.id])   // the good record survives
        }
    }

    @Test func missingFileReadsEmpty() {
        withTempLog { url in
            #expect(ReviewLog.records(from: url).isEmpty)
        }
    }

    @Test func resetRemovesTheLog() {
        withTempLog { url in
            ReviewLog.append(record(), to: url)
            #expect(!ReviewLog.records(from: url).isEmpty)
            ReviewLog.reset(at: url)
            #expect(ReviewLog.records(from: url).isEmpty)
        }
    }
}
