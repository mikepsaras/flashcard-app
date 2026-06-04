import SwiftUI
import SwiftData

/// Enter many cards at once. Three modes:
/// - **Pairs** — each row is its own Front + Back (a tidy grid).
/// - **Same back** — type one Back (e.g. "Germany"), then a list of Fronts → one card each.
/// - **Same front** — type one Front, then a list of Backs → one card each.
///
/// Reached from a deck's "+" menu, a section header ("Add Cards…"), and the empty-deck state. In the
/// single-line entry fields a pasted multi-line list splits into rows (Pairs also splits a tab/comma
/// into Front/Back).
struct BulkAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck

    /// What varies row-to-row. The "same" modes share one side (typed once) so you don't retype it.
    enum Mode: String, CaseIterable, Identifiable {
        case pairs, sameBack, sameFront
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pairs: "Pairs"
            case .sameBack: "Same back"
            case .sameFront: "Same front"
            }
        }
        var hint: String {
            switch self {
            case .pairs: "Each row becomes its own card."
            case .sameBack: "Every card shares the back above; add a front per card."
            case .sameFront: "Every card shares the front above; add a back per card."
            }
        }
    }

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var front = ""
        var back = ""
    }

    @State private var mode: Mode = .pairs
    @State private var rows: [Row]
    @State private var sharedFront = ""
    @State private var sharedBack = ""
    @State private var section: String
    @FocusState private var focused: UUID?

    init(deck: Deck, section: String = "") {
        self.deck = deck
        _rows = State(initialValue: [Row(), Row(), Row()])   // start with a few blank rows
        _section = State(initialValue: section)
    }

    /// The (front, back) pairs that will be inserted — also drives the count and Add button.
    private var drafts: [(front: String, back: String)] {
        Self.draftCards(mode: mode, rows: rows.map { ($0.front, $0.back) },
                        sharedFront: sharedFront, sharedBack: sharedBack)
    }
    private var canAdd: Bool {
        guard !drafts.isEmpty else { return false }
        // "Same front" needs the shared front; "same back" allows a blank back (a term-only card).
        if mode == .sameFront { return !sharedFront.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $mode.animation(.snappy)) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    Text(mode.hint)
                }

                if mode == .sameBack {
                    Section("Shared back") {
                        TextField("Back of every card", text: $sharedBack, axis: .vertical)
                            .font(Typography.body)
                    }
                } else if mode == .sameFront {
                    Section("Shared front") {
                        TextField("Front of every card", text: $sharedFront, axis: .vertical)
                            .font(Typography.body)
                    }
                }

                if !deck.sectionOrder.isEmpty {
                    Section {
                        Picker("Section", selection: $section) {
                            Text("None").tag("")
                            ForEach(deck.sectionOrder, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section {
                    ForEach($rows) { $row in rowField($row) }
                        .onDelete { rows.remove(atOffsets: $0) }
                    Button { addRow() } label: { Label("Add Row", systemImage: "plus") }
                } header: {
                    Text(entriesHeader)
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
                    Button("Add \(drafts.count)") { addAll() }.disabled(!canAdd)
                }
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 600)
        #endif
    }

    private var entriesHeader: String {
        let label: String
        switch mode {
        case .pairs: label = "cards"
        case .sameBack: label = "fronts"
        case .sameFront: label = "backs"
        }
        return "\(drafts.count) \(drafts.count == 1 ? String(label.dropLast()) : label)"
    }

    /// The per-row editor: two fields in Pairs, a single field in the shared modes. The varying
    /// field is single-line, so a newline can only come from a paste → split into rows.
    @ViewBuilder private func rowField(_ row: Binding<Row>) -> some View {
        let id = row.wrappedValue.id
        switch mode {
        case .pairs:
            VStack(alignment: .leading, spacing: 6) {
                TextField("Front", text: row.front)
                    .font(Typography.headline)
                    .focused($focused, equals: id)
                    .onSubmit { addRowIfLast(id) }
                    .onChange(of: row.wrappedValue.front) { _, v in if v.contains("\n") { paste(v, into: id) } }
                TextField("Back", text: row.back, axis: .vertical)
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .sameBack:
            TextField("Front", text: row.front)
                .focused($focused, equals: id)
                .onSubmit { addRowIfLast(id) }
                .onChange(of: row.wrappedValue.front) { _, v in if v.contains("\n") { paste(v, into: id) } }
        case .sameFront:
            TextField("Back", text: row.back)
                .focused($focused, equals: id)
                .onSubmit { addRowIfLast(id) }
                .onChange(of: row.wrappedValue.back) { _, v in if v.contains("\n") { paste(v, into: id) } }
        }
    }

    private func addRow() {
        let row = Row()
        rows.append(row)
        focused = row.id
    }

    /// Return on the last row adds a fresh one (rapid entry); on earlier rows it just commits.
    private func addRowIfLast(_ id: UUID) {
        guard rows.last?.id == id else { return }
        addRow()
    }

    // MARK: Paste-splitting

    /// Parses pasted multi-line text into (front, back) pairs — one per non-empty line, with a tab
    /// (TSV) or the first comma (CSV) splitting the two. Pure + static so it's unit-testable.
    static func parsePaste(_ text: String) -> [(front: String, back: String)] {
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
            .map { (front: $0.0, back: $0.1) }
    }

    /// Non-empty, trimmed lines — for splitting a pasted list into the single-field (shared) modes.
    static func parseLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Splits a multi-line paste in the varying field into rows beneath the pasted one.
    private func paste(_ text: String, into id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        switch mode {
        case .pairs:
            let parsed = Self.parsePaste(text)
            guard !parsed.isEmpty else { rows[index].front = text.trimmingCharacters(in: .whitespacesAndNewlines); return }
            rows[index].front = parsed[0].front
            rows[index].back = parsed[0].back
            rows.insert(contentsOf: parsed.dropFirst().map { Row(front: $0.front, back: $0.back) }, at: index + 1)
        case .sameBack:
            let lines = Self.parseLines(text)
            guard !lines.isEmpty else { rows[index].front = text.trimmingCharacters(in: .whitespacesAndNewlines); return }
            rows[index].front = lines[0]
            rows.insert(contentsOf: lines.dropFirst().map { Row(front: $0) }, at: index + 1)
        case .sameFront:
            let lines = Self.parseLines(text)
            guard !lines.isEmpty else { rows[index].back = text.trimmingCharacters(in: .whitespacesAndNewlines); return }
            rows[index].back = lines[0]
            rows.insert(contentsOf: lines.dropFirst().map { Row(back: $0) }, at: index + 1)
        }
    }

    // MARK: Build

    /// The (front, back) pairs to insert for a mode — pure, so the per-mode logic is unit-tested
    /// without the view. Rows whose varying side is blank are dropped; fronts are trimmed.
    static func draftCards(mode: Mode, rows: [(front: String, back: String)],
                           sharedFront: String, sharedBack: String) -> [(front: String, back: String)] {
        let sf = sharedFront.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [(front: String, back: String)] = []
        for row in rows {
            let front = row.front.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .pairs:
                guard !front.isEmpty else { continue }
                out.append((front, row.back))
            case .sameBack:
                guard !front.isEmpty else { continue }
                out.append((front, sharedBack))
            case .sameFront:
                guard !row.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                out.append((sf, row.back))
            }
        }
        return out
    }

    private func addAll() {
        let drafts = self.drafts
        guard !drafts.isEmpty else { dismiss(); return }
        // New cards land in the chosen section in row order, appended after any existing cards.
        if !section.isEmpty && !deck.sectionOrder.contains(section) { deck.sectionOrder.append(section) }
        var order = deck.nextSortOrder(inSection: section)
        for draft in drafts {
            context.insert(Card(term: draft.front, definition: draft.back,
                                deck: deck, section: section, sortOrder: order))
            order += 1
        }
        context.saveAndPersist(touching: deck)
        dismiss()
    }
}
