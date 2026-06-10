import SwiftUI
import SwiftData

/// Lists a deck's automatic backups (newest first) and restores one **in place** — the deck
/// keeps its identity/selection; only its content is replaced. Restoring snapshots the current
/// state first, so a restore is itself recoverable from this same sheet.
struct RestoreFromBackupView: View {
    let deck: Deck

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private struct Row: Identifiable {
        let entry: BackupEntry
        let cardCount: Int?
        var id: URL { entry.url }
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var pendingRestore: BackupEntry?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    ContentUnavailableView(
                        "No Backups Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Backups are created automatically — one per day when a deck changes, plus one whenever a deck or its file would be deleted or replaced.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(rows) { row in
                                backupRow(row)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Restore from Backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 480)
        #endif
        .task { await load() }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let entry = pendingRestore { restore(entry) }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let entry = pendingRestore {
                Text("“\(deck.displayName)” will be replaced with the backup from \(entry.date.formatted(date: .abbreviated, time: .shortened)). The current version is backed up first.")
            }
        }
        .alert("Couldn’t Restore", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That backup file couldn’t be read. The deck was left unchanged.")
        }
    }

    private func backupRow(_ row: Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.headline)
                if let count = row.cardCount {
                    Text("^[\(count) card](inflect: true)")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Restore") { pendingRestore = row.entry }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
                .font(.system(.callout, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func load() async {
        let found = DeckBackups.entries(forDeck: deck.id, inAny: DeckStore.libraryURLs())
        var built: [Row] = []
        for entry in found {
            built.append(Row(entry: entry, cardCount: await Self.cardCount(at: entry.url)))
        }
        rows = built
        loaded = true
    }

    /// Decodes a backup just for its card count — `nonisolated async`, so the (potentially
    /// large) JSON decode runs off the main actor.
    private nonisolated static func cardCount(at url: URL) async -> Int? {
        guard let data = try? Data(contentsOf: url),
              let dto = try? DeckCodec.decodeDTO(data) else { return nil }
        return dto.cards.count
    }

    private func restore(_ entry: BackupEntry) {
        guard let data = try? Data(contentsOf: entry.url),
              let dto = try? DeckCodec.decodeDTO(data) else {
            failed = true
            return
        }
        // The restore is itself recoverable: snapshot what's being replaced, into the same
        // library folder the backup lives in (no day gate — this is an explicit user action).
        let folder = DeckBackups.libraryFolder(of: entry)
        if let current = try? DeckCodec.encode(deck) {
            DeckBackups.writeBackup(current, forDeck: deck.id, in: folder, now: .now)
        }
        // In-place merge (the reconcile machinery): the deck keeps its persistentModelID, so
        // the sidebar selection and this detail view stay valid.
        DeckCodec.update(deck, from: dto, in: context)
        context.saveAndPersist(touching: deck)
        dismiss()
    }
}
