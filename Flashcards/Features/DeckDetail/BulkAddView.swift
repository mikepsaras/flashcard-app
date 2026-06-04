import SwiftUI
import SwiftData

/// Enter many cards at once: a grid of Front/Back rows. Reached from a deck's "+" menu, a section
/// header ("Add Cards…"), and the empty-deck state. Pasting multi-line text into a Front field
/// splits it into multiple rows — one card per line, with a tab or comma splitting term/definition.
struct BulkAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var term = ""
        var definition = ""
    }

    @State private var rows: [Row]
    @State private var section: String
    @FocusState private var focused: FieldID?

    private enum FieldID: Hashable { case term(UUID), definition(UUID) }

    init(deck: Deck, section: String = "") {
        self.deck = deck
        _rows = State(initialValue: [Row(), Row(), Row()])   // start with a few blank rows
        _section = State(initialValue: section)
    }

    private func isFilled(_ row: Row) -> Bool {
        !row.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var filledCount: Int { rows.filter(isFilled).count }

    var body: some View {
        NavigationStack {
            List {
                if !deck.sectionOrder.isEmpty {
                    Section {
                        Picker("Section", selection: $section) {
                            Text("None").tag("")
                            ForEach(deck.sectionOrder, id: \.self) { Text($0).tag($0) }
                        }
                    } footer: {
                        Text("New cards are added to this section.")
                    }
                }

                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Front", text: $row.term)
                                .font(Typography.headline)
                                .focused($focused, equals: .term(row.id))
                                .onChange(of: row.term) { _, newValue in
                                    // A newline can only arrive by paste (Return submits a single-line
                                    // field), so treat it as a multi-row paste and split it out.
                                    if newValue.contains("\n") { splitPaste(newValue, into: row.id) }
                                }
                            TextField("Back", text: $row.definition, axis: .vertical)
                                .font(Typography.callout)
                                .foregroundStyle(.secondary)
                                .focused($focused, equals: .definition(row.id))
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { rows.remove(atOffsets: $0) }

                    Button { addRow() } label: { Label("Add Row", systemImage: "plus") }
                } header: {
                    Text(filledCount == 1 ? "1 card" : "\(filledCount) cards")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Add Cards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(filledCount)") { addAll() }.disabled(filledCount == 0)
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
    }

    private func addRow() {
        let row = Row()
        rows.append(row)
        focused = .term(row.id)
    }

    /// Splits pasted multi-line text into rows: the first line fills the pasted row, each following
    /// line becomes a new row beneath it. Within a line, a tab (TSV) or the first comma (CSV) splits
    /// Front/Back. Distinct from the demoted file import — this just speeds up manual grid entry.
    /// Parses pasted multi-line text into (term, definition) pairs — one per non-empty line, with a
    /// tab (TSV) or the first comma (CSV) splitting the two. Pure + static so it's unit-testable.
    static func parsePaste(_ text: String) -> [(term: String, definition: String)] {
        func split(_ line: String) -> (String, String) {
            if let tab = line.firstIndex(of: "\t") {
                return (String(line[..<tab]).trimmingCharacters(in: .whitespaces),
                        String(line[line.index(after: tab)...]).trimmingCharacters(in: .whitespaces))
            }
            if let comma = line.firstIndex(of: ",") {
                return (String(line[..<comma]).trimmingCharacters(in: .whitespaces),
                        String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
            }
            return (line.trimmingCharacters(in: .whitespaces), "")
        }
        return text.components(separatedBy: .newlines)
            .map(split)
            .filter { !($0.0.isEmpty && $0.1.isEmpty) }
            .map { (term: $0.0, definition: $0.1) }
    }

    private func splitPaste(_ text: String, into id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let parsed = Self.parsePaste(text)
        guard !parsed.isEmpty else {
            rows[index].term = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        rows[index].term = parsed[0].term
        rows[index].definition = parsed[0].definition
        let newRows = parsed.dropFirst().map { Row(term: $0.term, definition: $0.definition) }
        rows.insert(contentsOf: newRows, at: index + 1)
    }

    private func addAll() {
        // New cards land in the chosen section in row order, appended after any existing cards.
        if !section.isEmpty && !deck.sectionOrder.contains(section) { deck.sectionOrder.append(section) }
        var order = deck.nextSortOrder(inSection: section)
        var added = 0
        for row in rows where isFilled(row) {
            context.insert(Card(
                term: row.term.trimmingCharacters(in: .whitespacesAndNewlines),
                definition: row.definition,
                deck: deck,
                section: section,
                sortOrder: order
            ))
            order += 1
            added += 1
        }
        if added > 0 { context.saveAndPersist(touching: deck) }
        dismiss()
    }
}
