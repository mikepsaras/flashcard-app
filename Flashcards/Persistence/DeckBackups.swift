import Foundation

/// One on-disk backup of a deck: a timestamped copy of its `.cards` bytes.
struct BackupEntry: Equatable, Sendable {
    let url: URL
    let date: Date
}

/// Retention rules for a deck's backups: keep the newest `keepCount`, drop anything older than
/// `maxAge` — but never the newest entry, however old (the last line of defense stays).
enum BackupPolicy {
    static let keepCount = 10
    static let maxAge: TimeInterval = 180 * 24 * 3600

    /// The entries that should be deleted under the policy. Pure — `entries` in any order.
    static func prunable(_ entries: [BackupEntry], now: Date) -> [BackupEntry] {
        let newestFirst = entries.sorted { $0.date > $1.date }
        guard newestFirst.count > 1 else { return [] }
        return newestFirst.dropFirst().enumerated().compactMap { index, entry in
            let position = index + 1   // rank among all entries, newest = 0
            if position >= keepCount { return entry }
            if now.timeIntervalSince(entry.date) > maxAge { return entry }
            return nil
        }
    }
}

/// Versioned per-deck backups, stored inside each library folder at
/// `.backups/<deckUUID>/<yyyyMMdd-HHmmssSSS>Z.cards`.
///
/// Why there: it rides with the deck's own folder (multi-folder correct, same volume and
/// permissions), the dot prefix hides it in Finder and the iOS Files app, and the loader /
/// watcher / prune never see it (`DeckStore.deckFiles` is non-recursive and a directory fails
/// the `.cards`-extension filter). `deleteAllDecks` removes only deck files, so backups survive
/// even a full reset.
///
/// Backups are **best-effort**: a failed backup never blocks or fails the primary write.
/// Everything here is nonisolated — called from the persist engine (off-main eventually) and
/// from reconcile on the main actor.
enum DeckBackups {
    static let directoryName = ".backups"

    /// Fixed-format UTC timestamp (millisecond resolution) used as the backup filename stem.
    /// POSIX locale + UTC keep names stable and lexically sortable across machines.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmssSSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func backupDirectory(forDeck id: UUID, in libraryFolder: URL) -> URL {
        libraryFolder
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func filename(for date: Date) -> String {
        "\(formatter.string(from: date))Z.\(DeckStore.fileExtension)"
    }

    static func date(fromFilename filename: String) -> Date? {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.hasSuffix("Z") else { return nil }
        return formatter.date(from: String(stem.dropLast()))
    }

    /// All backups for a deck in `libraryFolder`, newest first. Files that don't match the
    /// timestamp naming pattern are ignored (and never deleted by the retention prune).
    static func entries(forDeck id: UUID, in libraryFolder: URL) -> [BackupEntry] {
        let directory = backupDirectory(forDeck: id, in: libraryFolder)
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .compactMap { url in date(fromFilename: url.lastPathComponent).map { BackupEntry(url: url, date: $0) } }
            .sorted { $0.date > $1.date }
    }

    /// All backups for a deck across the whole library folder set, newest first (macOS
    /// multi-folder; a single folder on iOS).
    static func entries(forDeck id: UUID, inAny folders: [URL]) -> [BackupEntry] {
        folders.flatMap { entries(forDeck: id, in: $0) }.sorted { $0.date > $1.date }
    }

    /// The library folder a backup entry lives under (entry → `<uuid>/` → `.backups/` → folder).
    static func libraryFolder(of entry: BackupEntry) -> URL {
        entry.url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Whether the deck already has a backup from the same (UTC) day as `now` — the daily gate
    /// that keeps routine edits from piling up more than one snapshot per day.
    static func hasBackup(sameDayAs now: Date, deck id: UUID, in libraryFolder: URL) -> Bool {
        let day = formatter.string(from: now).prefix(8)
        return entries(forDeck: id, in: libraryFolder)
            .contains { formatter.string(from: $0.date).prefix(8) == day }
    }

    /// Writes `data` as a new timestamped backup for the deck, then applies the retention policy.
    /// Best-effort by design: failures are swallowed (the caller's primary write must proceed).
    @discardableResult
    static func writeBackup(_ data: Data, forDeck id: UUID, in libraryFolder: URL, now: Date) -> Bool {
        let directory = backupDirectory(forDeck: id, in: libraryFolder)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename(for: now))
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return false }
        for entry in BackupPolicy.prunable(entries(forDeck: id, in: libraryFolder), now: now) {
            try? FileManager.default.removeItem(at: entry.url)
        }
        return true
    }
}
