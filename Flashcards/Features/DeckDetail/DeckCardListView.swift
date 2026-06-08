import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One row of the flattened card list. Flattening the sections into a single `ForEach` is what lets
/// `.onMove` drag a card *across* section boundaries (SwiftUI's per-`Section` `ForEach` can't) — the
/// card's section is recomputed from where it lands. This mirrors how Reminders' list is built.
private enum CardListRow: Identifiable {
    case header(String)   // section name ("" = the unsectioned area)
    case empty(String)    // an empty section's drop hint
    case card(Card)
    var id: String {
        switch self {
        case .header(let name): "h-\(name.isEmpty ? "\u{0}cards" : name)"
        case .empty(let name): "e-\(name.isEmpty ? "\u{0}cards" : name)"
        case .card(let card): "c-\(card.id.uuidString)"
        }
    }
}

/// The editable card list for a deck: a flattened, drag-reorderable `List` with native selection,
/// section headers, the per-card and per-section menus, and the card-edit / card-delete /
/// rename-section modals. "Add cards", "New section", and bulk delete are reported upward via
/// closures because the toolbar drives them too; everything else this view does directly.
struct DeckCardListView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    @Binding var selection: Set<UUID>
    let cardSearch: String
    let otherDecks: [Deck]
    var onAddCards: (_ section: String) -> Void
    var onNewSection: (_ cards: [Card]) -> Void
    var onRequestBulkDelete: () -> Void
    /// Opens a card for editing. macOS routes this up to the full-window gallery; iOS ignores it and
    /// uses the local sheet (see `open(_:)`).
    var onOpenCard: (Card) -> Void = { _ in }
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif

    @State private var editingCard: Card?
    @State private var cardPendingDeletion: Card?
    @State private var sectionPendingRename: String?
    @State private var renameSectionName = ""

    private func filteredCards(_ cards: [Card]) -> [Card] {
        guard !cardSearch.isEmpty else { return cards }
        return cards.filter {
            $0.term.localizedCaseInsensitiveContains(cardSearch)
            || $0.definition.localizedCaseInsensitiveContains(cardSearch)
        }
    }

    /// Section groups for display, filtered by the card search. While searching, empty groups are
    /// hidden; otherwise empty named sections stay visible so they can be managed.
    private var displayGroups: [Deck.SectionGroup] {
        deck.sectionGroups.compactMap { group in
            let cards = filteredCards(group.cards)
            if cardSearch.isEmpty { return Deck.SectionGroup(name: group.name, cards: cards) }
            return cards.isEmpty ? nil : Deck.SectionGroup(name: group.name, cards: cards)
        }
    }

    /// The display groups flattened into a single row list (header, then its cards or an empty hint),
    /// so one `ForEach` + `.onMove` can drag cards within *and* between sections.
    private var flatRows: [CardListRow] {
        displayGroups.flatMap { group -> [CardListRow] in
            [.header(group.name)] + (group.cards.isEmpty ? [.empty(group.name)] : group.cards.map(CardListRow.card))
        }
    }

    var body: some View {
        cardList
            #if os(iOS)
            .sheet(item: $editingCard) { card in
                BulkAddView(deck: deck, editing: card)
            }
            #endif
            .confirmationDialog(
                "Delete this card?",
                isPresented: Binding(get: { cardPendingDeletion != nil }, set: { if !$0 { cardPendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: cardPendingDeletion
            ) { card in
                Button("Delete", role: .destructive) { deleteCard(card) }
                Button("Cancel", role: .cancel) {}
            } message: { card in
                Text("“\(card.term.isEmpty ? "This card" : card.term)” will be permanently deleted. This can’t be undone.")
            }
            .alert("Rename Section", isPresented: Binding(get: { sectionPendingRename != nil }, set: { if !$0 { sectionPendingRename = nil } })) {
                TextField("Section name", text: $renameSectionName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { if let old = sectionPendingRename { renameSection(old, to: renameSectionName) } }
            }
    }

    /// Opens a card for editing — the full-window gallery on macOS, the modal sheet on iOS.
    private func open(_ card: Card) {
        #if os(macOS)
        onOpenCard(card)
        #else
        editingCard = card
        #endif
    }

    private var cardList: some View {
        List(selection: $selection) {
            // Empty only when there are no cards AND no sections — a deck with sections (but no cards
            // yet) shows its section structure so you can build it out before adding cards.
            if deck.cardArray.isEmpty && deck.sectionOrder.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Text("No cards yet.")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button { onAddCards("") } label: { Label("Add a Card", systemImage: "plus") }
                            Button { onNewSection([]) } label: { Label("New Section", systemImage: "folder.badge.plus") }
                        }
                        .buttonStyle(.bordered)
                        .font(Typography.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            } else if !cardSearch.isEmpty && displayGroups.isEmpty {
                emptyRow("No cards match “\(cardSearch)”.")
            } else {
                // One ForEach over the flattened rows, so the native drag can move a card across
                // section boundaries. Headers/hints are pinned; a moved card's section is recomputed
                // from where it landed (see moveFlat) — exactly how Reminders behaves.
                ForEach(flatRows) { row in
                    switch row {
                    case .header(let name):
                        flatSectionHeader(name)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                    case .empty:
                        // NOT moveDisabled: a trailing move-disabled row blocks dropping a card past
                        // it, which made a newly-created (empty, last) section impossible to drag into.
                        // Leaving it movable makes the empty section a valid drop target; moveFlat
                        // ignores the hint itself, so dragging it is a harmless no-op after re-render.
                        Text("No cards yet — drag a card here, or use a card's ••• menu.")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .deleteDisabled(true)
                            .contextMenu { cardMenu(for: nil) }
                    case .card(let card):
                        cardRow(card)
                    }
                }
                .onMove { source, destination in moveFlat(from: source, to: destination) }
                .onDelete { offsets in deleteFlat(offsets) }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        // macOS keyboard niceties (the context menu + toolbar cover the same actions): Return opens
        // the single selected card, ⌘A selects all, and the Delete key removes the selection (with a
        // confirmation, via onDeleteCommand). A click is the list's native selection — never a tap
        // gesture — so it doesn't disable the native onMove drag (FB7367473).
        .onKeyPress(.return) {
            guard let card = singleSelectedCard else { return .ignored }
            open(card)
            return .handled
        }
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection = Set(deck.cardArray.map(\.id))
            return .handled
        }
        .onDeleteCommand { if !selection.isEmpty { onRequestBulkDelete() } }
        // Double-click-to-open, wired natively on the underlying NSTableView (NOT a SwiftUI tap
        // gesture, which would disable drag + click-select). The clicked row maps to flatRows.
        .background(TableDoubleClickHandler(onDoubleClick: { row in
            let rows = flatRows
            guard rows.indices.contains(row), case .card(let card) = rows[row] else { return }
            open(card)
        }, onRowDrag: {
            // A drag started in the table: drop any selected-but-not-dragged card so it doesn't
            // flicker mid-drag. moveFlat re-selects the dropped card when the drag finishes.
            if !selection.isEmpty { selection.removeAll() }
        }))
        #endif
    }

    @ViewBuilder private func cardRow(_ card: Card) -> some View {
        let row = CardRowView(card: card)
            .contentShape(Rectangle())
            .tag(card.id)
            .contextMenu { cardMenu(for: card) }
        #if os(iOS)
        // iOS: a tap opens the editor — but only outside Edit mode, where taps drive multi-select.
        if editMode?.wrappedValue.isEditing == true {
            row
        } else {
            row.onTapGesture { open(card) }
        }
        #else
        // macOS: NO tap gesture of ANY kind — even a *simultaneous* double-tap makes SwiftUI route
        // the press to gesture recognition, which disables the List's native drag-reorder AND
        // click-to-select (FB7367473; confirmed by testing). A click selects (native); Return or the
        // context-menu "Edit" opens; double-click opens via the underlying NSTableView's native
        // doubleAction (TableDoubleClickHandler), which coexists with drag/select since it isn't a
        // SwiftUI gesture.
        row
        #endif
    }

    /// The card context menu, reused for an actual card and for empty areas (an empty deck or an
    /// empty section's drop hint). With no card the card-specific actions grey out; "Add Card" and
    /// "New Section…" stay available so you can build out a deck that has no cards yet.
    @ViewBuilder private func cardMenu(for card: Card?) -> some View {
        let targets = card.map { contextTargets($0) } ?? []
        Button { if let card { open(card) } } label: { Label("Edit", systemImage: "pencil") }
            .disabled(card == nil)
        Button { duplicate(targets) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            .disabled(card == nil)
        Divider()
        Button { onAddCards(card?.section ?? "") } label: { Label("Add Card", systemImage: "plus") }
        Button { onNewSection(targets) } label: { Label("New Section…", systemImage: "folder.badge.plus") }
        Menu("Move to Section") {
            Button("None") { moveToSection(targets, "") }
                .disabled(card?.section.isEmpty ?? true)
            if !deck.sectionOrder.isEmpty { Divider() }
            ForEach(deck.sectionOrder, id: \.self) { name in
                Button(name) { moveToSection(targets, name) }
                    .disabled(card?.section == name)
            }
        }
        .disabled(card == nil)
        if !otherDecks.isEmpty {
            Menu("Move to Deck") {
                ForEach(otherDecks) { target in
                    Button(target.displayName) { moveCardsToDeck(targets, target) }
                }
            }
            .disabled(card == nil)
        }
        Divider()
        Button(role: .destructive) {
            if targets.count > 1 { onRequestBulkDelete() } else if let card { cardPendingDeletion = card }
        } label: { Label(card.map(deleteLabel) ?? "Delete", systemImage: "trash") }
            .disabled(card == nil)
    }

    /// A section header rendered as a row in the flattened list (styled to read like a `Section`
    /// header). `name == ""` is the unsectioned area.
    @ViewBuilder private func flatSectionHeader(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text(name.isEmpty ? "Cards" : name)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if !name.isEmpty {
                Menu {
                    Button { onAddCards(name) } label: { Label("Add Cards…", systemImage: "plus") }
                    Divider()
                    Button { startRenameSection(name) } label: { Label("Rename", systemImage: "pencil") }
                    Button { moveSection(name, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                        .disabled(deck.sectionOrder.first == name)
                    Button { moveSection(name, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                        .disabled(deck.sectionOrder.last == name)
                    Divider()
                    Button(role: .destructive) { deleteSection(name) } label: { Label("Delete Section", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.top, 10)
        .listRowSeparator(.hidden)
    }

    private func emptyRow(_ text: String) -> some View {
        Section {
            Text(text).font(Typography.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Mutations

    /// The cards a context-menu action affects: the whole selection when the right-clicked card is
    /// part of a multi-selection (like Finder/Mail), otherwise just that card.
    private func contextTargets(_ card: Card) -> [Card] {
        guard selection.contains(card.id), selection.count > 1 else { return [card] }
        // In display order (unsectioned first, then by section + sortOrder) so duplicates/moves keep
        // the cards' on-screen order — `cardArray` is the *unordered* relationship.
        return deck.sectionGroups.flatMap(\.cards).filter { selection.contains($0.id) }
    }

    /// "Delete" / "Delete N Cards" — the menu label reflects how many cards the action removes.
    private func deleteLabel(_ card: Card) -> String {
        let count = contextTargets(card).count
        return count > 1 ? "Delete \(count) Cards" : "Delete"
    }

    private func deleteFlat(_ offsets: IndexSet) {
        let rows = flatRows
        var deleted = false
        for index in offsets where index < rows.count {
            if case .card(let card) = rows[index] { context.delete(card); deleted = true }
        }
        if deleted { context.saveAndPersist(touching: deck) }
    }

    /// Apply an `.onMove` over the flattened rows: move the card, then recompute every card's section
    /// (the nearest preceding header) and its order within that section. This is what turns a single
    /// native drag into both within- and cross-section moves.
    private func moveFlat(from source: IndexSet, to destination: Int) {
        guard cardSearch.isEmpty else { return }   // order is ambiguous while filtering
        let rowsBefore = flatRows
        // The card(s) actually being dragged (header/hint rows can't move) — re-selected after the
        // drop so the selection follows the moved card instead of leaving a stale highlight behind.
        let draggedIDs = Set(source.compactMap { index -> UUID? in
            guard rowsBefore.indices.contains(index), case .card(let card) = rowsBefore[index] else { return nil }
            return card.id
        })
        var rows = rowsBefore
        rows.move(fromOffsets: source, toOffset: destination)
        var currentSection = ""
        var orderInSection: [String: Int] = [:]
        // Animate the reassignment so the list settles into its new order instead of snapping
        // (the rows are derived from the model, so the move isn't auto-animated by the List).
        withAnimation(.snappy) {
            for row in rows {
                switch row {
                case .header(let name): currentSection = name
                case .empty: break
                case .card(let card):
                    let order = orderInSection[currentSection, default: 0]
                    orderInSection[currentSection] = order + 1
                    if card.section != currentSection || card.sortOrder != order {
                        card.section = currentSection
                        card.sortOrder = order
                        card.modifiedAt = .now
                    }
                }
            }
            if !draggedIDs.isEmpty { selection = draggedIDs }
        }
        context.saveAndPersist(touching: deck)
    }

    private func deleteCard(_ card: Card) {
        context.delete(card)
        context.saveAndPersist(touching: deck)
    }

    /// Duplicates each card within its deck + section (fresh schedule, appended to the section).
    /// Operates on the whole selection when invoked on a multi-selection.
    private func duplicate(_ cards: [Card]) {
        var nextOrder: [String: Int] = [:]
        for card in cards {
            let order = nextOrder[card.section] ?? deck.nextSortOrder(inSection: card.section)
            nextOrder[card.section] = order + 1
            // Preserve the per-card answer mode + elaboration on a duplicate (fresh schedule), so a
            // cloze/type card stays itself rather than reverting to the deck default.
            let copyCard = Card(term: card.term, definition: card.definition, deck: deck,
                                section: card.section, sortOrder: order)
            copyCard.answerModeRaw = card.answerModeRaw
            copyCard.extra = card.extra
            context.insert(copyCard)
        }
        context.saveAndPersist(touching: deck)
    }

    #if os(macOS)
    /// The single selected card, or nil if zero/multiple are selected — used by Return-to-open.
    private var singleSelectedCard: Card? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return deck.cardArray.first { $0.id == id }
    }
    #endif

    /// Moves the cards into `target`, dropping their section (its names belong to this deck) and
    /// clearing the selection. Operates on the whole selection from a multi-selection.
    private func moveCardsToDeck(_ cards: [Card], _ target: Deck) {
        guard !cards.isEmpty else { return }
        var order = target.nextSortOrder(inSection: "")
        for card in cards {
            card.deck = target
            card.section = ""
            card.sortOrder = order
            card.modifiedAt = .now
            order += 1
        }
        selection.removeAll()
        context.saveAndPersist(touching: deck, target)
    }

    // MARK: Card sections

    /// Moves the cards into the named section (or "" for unsectioned), appending in order. Operates
    /// on the whole selection from a multi-selection; cards already in the section are left untouched.
    private func moveToSection(_ cards: [Card], _ name: String) {
        var order = deck.nextSortOrder(inSection: name)
        var changed = false
        withAnimation(.snappy) {
            for card in cards where card.section != name {
                card.section = name
                card.sortOrder = order
                card.modifiedAt = .now
                order += 1
                changed = true
            }
        }
        if changed { context.saveAndPersist(touching: deck) }
    }

    private func moveSection(_ name: String, by offset: Int) {
        withAnimation(.snappy) { deck.moveSection(name, by: offset) }
        context.saveAndPersist(touching: deck)
    }

    private func startRenameSection(_ name: String) {
        renameSectionName = name
        sectionPendingRename = name
    }

    private func renameSection(_ old: String, to rawNew: String) {
        let new = String(rawNew.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !new.isEmpty, new != old else { return }
        if let idx = deck.sectionOrder.firstIndex(of: old) {
            // Merge into an existing section if the new name is already taken; else rename in place.
            if deck.sectionOrder.contains(new) { deck.sectionOrder.remove(at: idx) }
            else { deck.sectionOrder[idx] = new }
        }
        for card in deck.cardArray where card.section == old {
            card.section = new
            card.modifiedAt = .now
        }
        context.saveAndPersist(touching: deck)
    }

    private func deleteSection(_ name: String) {
        deck.sectionOrder.removeAll { $0 == name }
        for card in deck.cardArray where card.section == name {
            card.section = ""
            card.modifiedAt = .now
        }
        context.saveAndPersist(touching: deck)
    }
}

private struct CardRowView: View {
    let card: Card

    /// Soonest due date across the directions this card's deck actually studies.
    private var nextDue: Date {
        (card.deck?.studyReversed ?? false) ? min(card.dueDate, card.reverseDueDate) : card.dueDate
    }
    private var isDueNow: Bool { nextDue <= .now }
    private var daysUntilDue: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: nextDue)).day ?? 0
        return max(days, 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.term.isEmpty ? AttributedString("—") : Markdown.previewLine(card.term))
                    .font(Typography.headline)
                    .lineLimit(1)
                Text(Markdown.previewLine(card.definition))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                healthBadge
                // A suspended card is out of study, so its "Due"/"New" schedule state would mislead.
                if !card.suspended { scheduleBadge }
            }
        }
        .padding(.vertical, 3)
        .opacity(card.suspended ? 0.6 : 1)   // visibly dim a parked leech
        .contentShape(Rectangle())
    }

    /// Leech / suspended flag (S7.4), shown ahead of the schedule badge. A suspended card shows only
    /// this; an active leech shows it alongside the schedule badge.
    @ViewBuilder private var healthBadge: some View {
        if card.suspended {
            labeledPill("Suspended", systemImage: "pause.circle.fill", color: .secondary)
                .help("Suspended — held out of study. Open the card to resume.")
        } else if card.isLeech {
            labeledPill("Leech", systemImage: "exclamationmark.triangle.fill", color: .orange)
                .help("Leech — failed \(card.lapses) times. Open the card to suspend or reset.")
        }
    }

    private func labeledPill(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder private var scheduleBadge: some View {
        if !card.hasBeenReviewed {
            pill("New", color: Theme.accent)
        } else if isDueNow {
            pill("Due", color: .orange)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text("\(daysUntilDue)d")
            }
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .help("Next review \(nextDue.formatted(date: .abbreviated, time: .omitted))")
            .accessibilityLabel("Next review in \(daysUntilDue) \(daysUntilDue == 1 ? "day" : "days")")
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
