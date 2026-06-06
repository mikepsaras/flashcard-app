import Foundation

/// Append-only per-review history — one JSON object per line in `reviewlog.jsonl` in the app's private
/// Application Support folder (NOT the user's visible deck folder). The substrate for FSRS weight
/// optimization, calibration (predicted vs. actual), Elo, and coverage trends; no feature consumes it
/// yet — this is the Phase 1 enabler (S1.3). The card model stores only each card's *last* review, so
/// this is the only place the full history lives.
///
/// Undo appends a `void` line referencing the record's id rather than rewriting the file, so the log
/// stays strictly append-only; `records()` nets voids out. Device-local — it doesn't follow a synced
/// library folder across devices. Best-effort: a write failure is swallowed, since the log is analytics
/// and never the schedule's source of truth.
enum ReviewLog {
    /// One recorded review. `id` lets an undo void it without rewriting the file.
    struct Record: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var ts: Date                  // when it was reviewed
        var deck: UUID
        var card: UUID
        var direction: ReviewDirection
        var grade: Int                // Grade raw value (0/3/4/5)
        var correct: Bool
        var elapsedDays: Double        // days since the previous review of this unit (0 if new)
        var intervalBefore: Int        // the studied direction's scheduled interval at review time
        var mature: Bool               // was the unit mature (interval ≥ threshold) at review time
    }

    static let fileName = "reviewlog.jsonl"
    static func fileURL(in directory: URL) -> URL { directory.appendingPathComponent(fileName) }

    /// The app-private folder for the log — `Application Support/Flashcards`, created on demand. Out
    /// of the user's visible deck folder, and device-local (not synced with the library folder).
    static var defaultDirectory: URL { resolvedDirectory }
    /// The log file in `defaultDirectory`.
    static var defaultURL: URL { fileURL(in: defaultDirectory) }

    private static let resolvedDirectory: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Flashcards", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// One-time relocation: if an earlier build wrote the log into the (visible) library folder, move
    /// it into Application Support. Best-effort; safe to call at every launch.
    static func migrateLegacy(from legacyDirectory: URL, to newURL: URL = defaultURL) {
        let old = fileURL(in: legacyDirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), old != newURL else { return }
        if fm.fileExists(atPath: newURL.path) {
            try? fm.removeItem(at: old)      // new location already has a log — drop the stray copy
        } else {
            try? fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: old, to: newURL)
        }
    }

    // MARK: Write

    /// Appends a review record as one line.
    static func append(_ record: Record, to url: URL) {
        guard let line = encodeLine(record) else { return }
        appendRaw(line, to: url)
    }

    /// Appends a void marker for a previously-logged record (used on undo), so `records()` drops it.
    static func void(_ id: UUID, to url: URL) {
        appendRaw(#"{"void":"\#(id.uuidString)"}"#, to: url)
    }

    /// Removes the log entirely (Reset progress / dev cleanup). No-op if absent.
    static func reset(at url: URL) { try? FileManager.default.removeItem(at: url) }

    // MARK: Read

    /// Every non-voided record, in file order. Corrupt or unrecognized lines are skipped, so a
    /// partially-written tail or a future schema change can't break reading the rest.
    static func records(from url: URL) -> [Record] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var voided = Set<UUID>()
        var records: [Record] = []
        for line in text.split(separator: "\n") {
            let data = Data(line.utf8)
            if let record = try? decoder.decode(Record.self, from: data) {
                records.append(record)
            } else if let marker = try? decoder.decode(VoidMarker.self, from: data) {
                voided.insert(marker.void)
            }
            // anything else is a corrupt/unknown line — skip it
        }
        return records.filter { !voided.contains($0.id) }
    }

    // MARK: Internals

    private struct VoidMarker: Codable { var void: UUID }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func encodeLine(_ record: Record) -> String? {
        (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Appends a single line (newline-terminated), creating the file (and folder) on first write.
    private static func appendRaw(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}
