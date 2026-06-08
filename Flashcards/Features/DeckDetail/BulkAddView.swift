import SwiftUI
import SwiftData

/// The unified card composer — adds one card or many. Opens with `startCount` cards (1 by default)
/// and grows via "Add Card"; a single card shows no "Card N" header so it reads like a plain editor.
/// Front is single-line (so pasting a list splits it into cards, and Return adds the next); Back is
/// the rich multi-line field. The Add-Card split button's menu reuses the previous card's front/back
/// for shared-side batches, and the counter adds several at once. Pass `editing:` to edit one existing
/// card instead — Front/Back become multi-line, with Elaboration + card-health, and Save writes it back.
struct BulkAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck
    /// When non-nil, the composer edits this existing card instead of adding new ones (1.8.0 unify).
    let editing: Card?

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var front = ""
        var back = ""
        /// Which face of this card is being edited (flip/type). Cloze ignores it (single face).
        var showingBack = false
    }

    private enum SharedSide {
        case front, back
        var title: String { self == .back ? "Same back" : "Same front" }
        var prompt: String { self == .back ? "Shared back" : "Shared front" }
    }

    @State private var rows: [Row]
    @State private var section: String
    /// The answer mode for the whole batch (flip / type / cloze), defaulting to the deck's default.
    @State private var answerMode: AnswerMode
    /// Elaboration text — edit-mode only (the batch-add flow doesn't set it).
    @State private var extra: String
    @State private var addCount = 1
    @State private var addCountText = "1"
    @State private var sharedSide: SharedSide?
    @State private var sharedValue = ""
    @FocusState private var focused: CardEditorField?

    /// The deck's accent color — the editable card matches the study card's tint.
    private var accent: Color { Color(hex: deck.colorHex) }

    init(deck: Deck, section: String = "", startCount: Int = 1, editing: Card? = nil) {
        self.deck = deck
        self.editing = editing
        if let card = editing {
            _rows = State(initialValue: [Row(front: card.term, back: card.definition)])
            _section = State(initialValue: card.section)
            _answerMode = State(initialValue: card.resolvedAnswerMode(deckDefault: deck.defaultAnswerMode))
            _extra = State(initialValue: card.extra)
        } else {
            _rows = State(initialValue: (0..<max(startCount, 1)).map { _ in Row() })
            _section = State(initialValue: section)
            _answerMode = State(initialValue: deck.defaultAnswerMode)
            _extra = State(initialValue: "")
        }
    }

    private func isFilled(_ row: Row) -> Bool {
        !row.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var filledCount: Int { rows.filter(isFilled).count }
    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modeRow
                    if !isEditing, !deck.sectionOrder.isEmpty { sectionRow }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, _ in
                        cardRow(index, $rows[index])
                    }
                    if isEditing {
                        elaborationField
                        if let card = editing, card.lapses > 0 || card.suspended { cardHealthSection(card) }
                    } else {
                        addControls
                    }
                    Text(hintText)
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.groupedBackground)
            .navigationTitle(isEditing ? "Edit Card" : (rows.count == 1 ? "New Card" : "Add Cards"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("Save") { saveEdit() }.disabled(filledCount == 0)
                    } else {
                        Button("Add \(filledCount)") { addAll() }.disabled(filledCount == 0)
                    }
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

    /// Answer mode for the whole batch (1.8.0). Set once here; per-card overrides live in the card editor.
    private var modeRow: some View {
        HStack {
            Text("Answer mode").font(Typography.body)
            Spacer(minLength: 8)
            Picker("Answer mode", selection: $answerMode.animation()) {
                ForEach(AnswerMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fieldBox()
    }

    private var isCloze: Bool { answerMode == .cloze }

    private var hintText: String {
        isCloze
            ? "Wrap answers in {{c1::…}} — the blanks show right on the card. Markdown & LaTeX ($…$) supported."
            : "Edit the card as you'll study it — tap Flip to edit the back. Markdown & LaTeX ($…$) supported."
    }

    /// One card, rendered as the **editable study card** itself: you edit the front right on the front
    /// face and flip it to edit the back (cloze is one face with the blanks visible). Two-plus cards get
    /// a small "Card N" header + remove above the card; a single card is just the card. A cloze card
    /// shows a live "in study" preview beneath; flip/type cards are already WYSIWYG, so they preview only
    /// when there's Markdown/LaTeX worth rendering.
    @ViewBuilder private func cardRow(_ index: Int, _ row: Binding<Row>) -> some View {
        let id = row.wrappedValue.id
        VStack(alignment: .leading, spacing: 10) {
            if rows.count > 1 {
                HStack {
                    Text("Card \(index + 1)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { delete(id) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove this card")
                }
            }

            EditableFlashcard(
                id: id,
                front: row.front,
                back: row.back,
                showingBack: row.showingBack,
                mode: answerMode,
                backLabel: deck.backLabel,
                section: section.isEmpty ? nil : section,
                accent: accent,
                minHeight: isEditing ? 280 : 230,
                rapidFront: !isEditing,
                onFrontSubmit: { addRowIfLast(id) },
                focus: $focused
            )
            // Rapid-add paste-splitting (non-cloze): a delimited multi-line paste in the front becomes
            // one card per line. Editing one card never splits; cloze is a single field.
            .onChange(of: row.wrappedValue.front) { _, v in
                if !isEditing, !isCloze, v.contains("\n") { paste(v, into: id) }
            }

            if isCloze {
                if !row.wrappedValue.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bulkPreview(front: row.wrappedValue.front, back: row.wrappedValue.back, cloze: true)
                }
            } else if hasFormatting(row.wrappedValue.front) || hasFormatting(row.wrappedValue.back) {
                bulkPreview(front: row.wrappedValue.front, back: row.wrappedValue.back, cloze: false)
            }
        }
    }

    /// Whether a field contains markdown/LaTeX worth previewing — so plain rows stay compact and only
    /// formatted ones reveal a live render.
    private func hasFormatting(_ s: String) -> Bool {
        s.contains(where: { "$*_#`>[".contains($0) })
            || s.range(of: "(^|\\n)\\s*([-+]\\s|\\d+[.)]\\s)", options: .regularExpression) != nil
    }

    /// Live render of a formatted row, in the same markdown+LaTeX engine the card uses.
    @ViewBuilder private func bulkPreview(front: String, back: String, cloze: Bool) -> some View {
        // Mirror how the card appears in study: a cloze shows the blanked prompt + the revealed answer.
        let shownFront = cloze ? Cloze.front(front) : front
        let shownBack = cloze ? Cloze.back(front) : back
        VStack(alignment: .leading, spacing: 6) {
            Label("Preview", systemImage: "eye")
                .font(.system(.caption2, weight: .medium)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 6) {
                if !shownFront.isEmpty { MarkdownText(text: shownFront, baseSize: 15, weight: .semibold) }
                if !shownBack.isEmpty {
                    MarkdownText(text: shownBack, baseSize: 14, mathColor: MathColor.secondary).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.windowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.top, 2)
    }

    private var addControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button { startShared(.back) } label: { Label("Same back…", systemImage: "rectangle.on.rectangle") }
                Button { startShared(.front) } label: { Label("Same front…", systemImage: "rectangle.on.rectangle") }
            } label: {
                Label("Add Card", systemImage: "plus")
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
            Stepper("Cards to add", value: $addCount, in: 1...100).labelsHidden()
            #endif
            Text(addCount == 1 ? "card" : "cards").font(Typography.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func addRows(count: Int = 1, front: String = "", back: String = "") {
        // A shared-front batch lands you on the back face (the side still to fill); otherwise the front.
        let showBack = !front.isEmpty
        let newRows = (0..<max(count, 1)).map { _ in Row(front: front, back: back, showingBack: showBack) }
        rows.append(contentsOf: newRows)
        if let first = newRows.first {
            focused = showBack ? .back(first.id) : .front(first.id)
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
        // Store the mode explicitly only when it differs from the deck default, so a card matching the
        // default re-encodes without an answerMode key (inherit). Cloze (never a deck default) is always set.
        let explicitMode = answerMode == deck.defaultAnswerMode ? "" : answerMode.rawValue
        var added = 0
        for row in rows where isFilled(row) {
            // Keep `row.back` verbatim even for cloze (a new cloze row never fills it, so it's ""; an
            // edited card keeps its prior back) — never blank a back the user can't see, so switching
            // a card to cloze and back doesn't lose its answer. Cloze ignores `definition` in study.
            let card = Card(term: row.front.trimmingCharacters(in: .whitespacesAndNewlines),
                            definition: row.back, deck: deck, section: section, sortOrder: order)
            card.answerModeRaw = explicitMode
            context.insert(card)
            order += 1
            added += 1
        }
        if added > 0 { context.saveAndPersist(touching: deck) }
        dismiss()
    }

    // MARK: Edit mode (1.8.0 unify — folds in the former CardEditorView)

    private var elaborationField: some View {
        VStack(alignment: .leading, spacing: 7) {
            MultilineField(label: "Elaboration", placeholder: "Optional — a “why”, a worked example, or a source.", text: $extra, minHeight: 72)
            Text("Shown beneath the answer while studying. Supports Markdown & LaTeX.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Writes the single row back onto the card being edited (vs `addAll`, which inserts new cards).
    private func saveEdit() {
        guard let card = editing, let row = rows.first else { return }
        card.term = row.front.trimmingCharacters(in: .whitespacesAndNewlines)
        // Don't blank the back when the mode is cloze — the Back field is hidden in cloze mode, so
        // `row.back` still holds the card's original answer; wiping it would silently lose data on a
        // flip→cloze switch. (Cloze ignores `definition` in study anyway.)
        card.definition = row.back
        card.extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        card.answerModeRaw = answerMode == deck.defaultAnswerMode ? "" : answerMode.rawValue
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck)
        dismiss()
    }

    /// Leech / card-health controls (S7.4): lapse count + Suspend / Reset Lapses. These act immediately
    /// (distinct from Save), so toggling suspension doesn't depend on also saving text edits.
    private func cardHealthSection(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: card.isLeech ? "exclamationmark.triangle.fill" : "stethoscope")
                    .foregroundStyle(card.isLeech ? .orange : .secondary)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.isLeech ? "Leech" : "Card Health")
                        .font(.system(.subheadline, weight: .semibold))
                    Text(healthSubtitle(card))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {
                    card.suspended.toggle()
                    persistHealthChange(card)
                } label: {
                    Label(card.suspended ? "Resume" : "Suspend", systemImage: card.suspended ? "play.circle" : "pause.circle")
                }
                Button {
                    card.lapses = 0
                    persistHealthChange(card)
                } label: {
                    Label("Reset Lapses", systemImage: "arrow.counterclockwise")
                }
                .disabled(card.lapses == 0)
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .font(Typography.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldBox()
    }

    private func healthSubtitle(_ card: Card) -> String {
        let lapseText = card.lapses == 1 ? "Failed once" : "Failed \(card.lapses) times"
        if card.suspended {
            return card.lapses == 0 ? "Held out of study." : "\(lapseText) · held out of study."
        }
        if card.isLeech { return "\(lapseText) — consider reformulating or suspending it." }
        return lapseText + "."
    }

    private func persistHealthChange(_ card: Card) {
        card.modifiedAt = .now
        context.saveAndPersist(touching: deck)
    }
}
