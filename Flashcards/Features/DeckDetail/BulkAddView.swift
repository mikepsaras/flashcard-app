import SwiftUI
import SwiftData

/// Enter many cards at once — Front/Back rows styled like the rest of the editors (fieldBox fields on
/// the grouped background). The **Add Row** split button adds the number of rows set in the little
/// counter beside it; its menu reuses the previous row's Back or Front, so several cards that share a
/// side (e.g. five backed "Germany") don't need it retyped. Pasting a multi-line list into a Front
/// field splits it into rows (a tab or the first comma splits Front/Back).
struct BulkAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var front = ""
        var back = ""
    }

    private enum Field: Hashable { case front(UUID), back(UUID) }
    private enum SharedSide {
        case front, back
        var title: String { self == .back ? "Same back" : "Same front" }
        var prompt: String { self == .back ? "Shared back" : "Shared front" }
    }

    @State private var rows: [Row]
    @State private var section: String
    @State private var addCount = 1
    @State private var addCountText = "1"
    @State private var sharedSide: SharedSide?
    @State private var sharedValue = ""
    @FocusState private var focused: Field?

    init(deck: Deck, section: String = "") {
        self.deck = deck
        _rows = State(initialValue: [Row(), Row(), Row()])
        _section = State(initialValue: section)
    }

    private func isFilled(_ row: Row) -> Bool {
        !row.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var filledCount: Int { rows.filter(isFilled).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !deck.sectionOrder.isEmpty { sectionRow }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, _ in
                        cardRow(index, $rows[index])
                    }
                    addControls
                    Text("Front & back support Markdown and LaTeX ($…$) — a preview appears as you format.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.groupedBackground)
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
            .alert(sharedSide?.title ?? "", isPresented: Binding(get: { sharedSide != nil }, set: { if !$0 { sharedSide = nil } }), presenting: sharedSide) { side in
                TextField(side.prompt, text: $sharedValue)
                Button("Cancel", role: .cancel) {}
                Button("Add \(addCount)") { commitShared(side) }
            } message: { side in
                Text("Adds \(addCount) card\(addCount == 1 ? "" : "s") sharing this \(side == .back ? "back" : "front"); fill in the \(side == .back ? "fronts" : "backs") after.")
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }

    private var sectionRow: some View {
        HStack {
            Text("Section").font(Typography.body)
            Spacer(minLength: 8)
            Picker("Section", selection: $section) {
                Text("None").tag("")
                ForEach(deck.sectionOrder, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fieldBox()
    }

    /// One card as a titled group ("Card N") with labeled Front/Back fields — so each Front/Back
    /// pair reads as its own card and the labels stay visible as you type (unlike placeholders).
    @ViewBuilder private func cardRow(_ index: Int, _ row: Binding<Row>) -> some View {
        let id = row.wrappedValue.id
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Card \(index + 1)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if rows.count > 1 {
                    Button { delete(id) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove this card")
                }
            }
            bulkField("Front") {
                TextField("", text: row.front)
                    .focused($focused, equals: .front(id))
                    .onSubmit { addRowIfLast(id) }
                    .onChange(of: row.wrappedValue.front) { _, v in if v.contains("\n") { paste(v, into: id) } }
            }
            bulkField("Back") {
                TextField("", text: row.back, axis: .vertical)
                    .foregroundStyle(.secondary)
                    .focused($focused, equals: .back(id))
            }
            if hasFormatting(row.wrappedValue.front) || hasFormatting(row.wrappedValue.back) {
                bulkPreview(front: row.wrappedValue.front, back: row.wrappedValue.back)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    /// Whether a field contains markdown/LaTeX worth previewing — so plain rows stay compact and only
    /// formatted ones reveal a live render.
    private func hasFormatting(_ s: String) -> Bool {
        s.contains(where: { "$*_#`>[".contains($0) })
            || s.range(of: "(^|\\n)\\s*([-+]\\s|\\d+[.)]\\s)", options: .regularExpression) != nil
    }

    /// Live render of a formatted row, in the same markdown+LaTeX engine the card uses.
    @ViewBuilder private func bulkPreview(front: String, back: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Preview", systemImage: "eye")
                .font(.system(.caption2, weight: .medium)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 6) {
                if !front.isEmpty { MarkdownText(text: front, baseSize: 15, weight: .semibold) }
                if !back.isEmpty {
                    MarkdownText(text: back, baseSize: 14, mathColor: MathColor.secondary).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.windowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.top, 2)
    }

    /// A captioned field box for a bulk-add row (label above, the field inside the standard box).
    @ViewBuilder private func bulkField<Content: View>(_ label: String, @ViewBuilder _ field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
            field()
                .textFieldStyle(.plain)
                .font(Typography.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .fieldBox()
        }
    }

    private var addControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button { startShared(.back) } label: { Label("Same back…", systemImage: "rectangle.on.rectangle") }
                Button { startShared(.front) } label: { Label("Same front…", systemImage: "rectangle.on.rectangle") }
            } label: {
                Label("Add Row", systemImage: "plus")
            } primaryAction: {
                addRows(count: addCount)
            }
            .fixedSize()

            TextField("", text: $addCountText)
                .multilineTextAlignment(.center)
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onChange(of: addCountText) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(3))
                    if filtered != newValue { addCountText = filtered; return }
                    if let value = Int(filtered) { addCount = min(max(value, 1), 100) }
                }
                .onChange(of: addCount) { _, newValue in
                    if addCountText != String(newValue) { addCountText = String(newValue) }
                }
            #if os(macOS)
            Stepper("Rows to add", value: $addCount, in: 1...100).labelsHidden()
            #endif
            Text(addCount == 1 ? "row" : "rows").font(Typography.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func addRows(count: Int = 1, front: String = "", back: String = "") {
        let newRows = (0..<max(count, 1)).map { _ in Row(front: front, back: back) }
        rows.append(contentsOf: newRows)
        if let first = newRows.first {
            // Focus the side still to be filled (the shared side, if any, is prefilled).
            focused = front.isEmpty ? .front(first.id) : .back(first.id)
        }
    }

    /// Opens the "Same back/front" prompt, pre-filled with the last row's value for that side — so it
    /// defaults to the most recent value but the user can type a custom one.
    private func startShared(_ side: SharedSide) {
        sharedValue = (side == .back ? rows.last?.back : rows.last?.front) ?? ""
        sharedSide = side
    }

    private func commitShared(_ side: SharedSide) {
        switch side {
        case .back:  addRows(count: addCount, back: sharedValue)
        case .front: addRows(count: addCount, front: sharedValue)
        }
        sharedSide = nil
    }

    /// Return on the last row adds a single fresh one (rapid entry); on earlier rows it just commits.
    private func addRowIfLast(_ id: UUID) {
        guard rows.last?.id == id else { return }
        addRows(count: 1)
    }

    private func delete(_ id: UUID) {
        guard rows.count > 1 else { return }
        rows.removeAll { $0.id == id }
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

    private func paste(_ text: String, into id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let parsed = Self.parsePaste(text)
        guard !parsed.isEmpty else {
            rows[index].front = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        rows[index].front = parsed[0].front
        rows[index].back = parsed[0].back
        rows.insert(contentsOf: parsed.dropFirst().map { Row(front: $0.front, back: $0.back) }, at: index + 1)
    }

    private func addAll() {
        // New cards land in the chosen section in row order, appended after any existing cards.
        if !section.isEmpty && !deck.sectionOrder.contains(section) { deck.sectionOrder.append(section) }
        var order = deck.nextSortOrder(inSection: section)
        var added = 0
        for row in rows where isFilled(row) {
            context.insert(Card(term: row.front.trimmingCharacters(in: .whitespacesAndNewlines),
                                definition: row.back, deck: deck, section: section, sortOrder: order))
            order += 1
            added += 1
        }
        if added > 0 { context.saveAndPersist(touching: deck) }
        dismiss()
    }
}
