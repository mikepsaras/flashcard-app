import SwiftUI
import SwiftData

/// The full-window deck **gallery editor** (macOS): the selected card fills the top as the editable
/// study card itself (`EditableFlashcard`), and a filmstrip of every card runs along the bottom —
/// scrub it with ← / → or click a thumbnail to pull that card up to edit. A "+" tile at the end of the
/// strip animates on hover and swooshes a fresh card into the deck. Edits go **live** to the cards
/// (no draft/Save modal); the deck persists on navigation, add/delete, and close. Replaces the modal
/// composer on macOS — the in-place editable card is reused as the hero.
struct DeckGalleryView: View {
    @Environment(\.modelContext) private var context
    @Bindable var deck: Deck
    /// The card to open on (a double-clicked card). `nil` ⇒ "New Card": add a blank one and edit it.
    let initialCardID: UUID?
    let onClose: () -> Void

    @State private var selectedID: UUID?
    /// Which face of the hero card is up (one card edits at a time, so a single flag suffices).
    @State private var showingBack = false
    @FocusState private var cardFocus: CardEditorField?
    /// Guards the one-time "New Card" auto-add so re-renders don't keep inserting blanks.
    @State private var didAutoOpen = false

    private var accent: Color { Color(hex: deck.colorHex) }

    /// Every card in display order (unsectioned first, then each section) — the filmstrip + ← / → order.
    private var orderedCards: [Card] { deck.sectionGroups.flatMap(\.cards) }
    private var selectedCard: Card? { orderedCards.first { $0.id == selectedID } ?? orderedCards.first }
    /// True while a card's text editor has focus — arrow keys then move the caret, not the selection.
    private var isEditingText: Bool { cardFocus != nil }

    private var topBarLeadingInset: CGFloat {
        #if os(macOS)
        72   // clear the overlaid traffic lights (full-size-content title bar, like Study)
        #else
        Theme.Spacing.m
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if let card = selectedCard {
                    heroArea(card)
                } else {
                    emptyHero
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            filmstrip
        }
        .background(Theme.windowBackground)
        .background(navigationKeys)
        .background(addCardShortcut)
        #if os(macOS)
        // Esc is two-stage: finish editing (commit → re-render) if a face is being edited, else close.
        // (`onExitCommand` is macOS-only; the gallery editor is macOS-only too, so this is never reached
        // on iOS — but the file still compiles for the iOS target, so the modifier must be guarded.)
        .onExitCommand { if cardFocus != nil { cardFocus = nil } else { close() } }
        #endif
        .onAppear(perform: openInitial)
        .onChange(of: selectedID) { _, _ in showingBack = false }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Done editing")
            .accessibilityLabel("Done")

            VStack(alignment: .leading, spacing: 1) {
                Text(deck.displayName).font(Typography.headline).lineLimit(1)
                Text(positionSubtitle).font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            if let card = selectedCard {
                modeChip(card)
                cardMenu(card)
            }
        }
        .padding(.leading, topBarLeadingInset)
        .padding(.trailing, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var positionSubtitle: String {
        let cards = orderedCards
        guard !cards.isEmpty else { return "No cards" }
        if let id = selectedID, let i = cards.firstIndex(where: { $0.id == id }) {
            return "Card \(i + 1) of \(cards.count)"
        }
        return "\(cards.count) card\(cards.count == 1 ? "" : "s")"
    }

    /// A compact mode "chip" (icon + one-word mode + chevron) that opens a checkmarked list of the three
    /// answer modes with icons — nicer than a bare menu picker, and NOT a segmented control (the user
    /// reads those as tabs).
    private func modeChip(_ card: Card) -> some View {
        let current = card.resolvedAnswerMode(deckDefault: deck.defaultAnswerMode)
        return Menu {
            Picker("Answer mode", selection: modeBinding(card)) {
                ForEach(AnswerMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: current.symbolName).font(.system(size: 11, weight: .semibold))
                Text(current.shortTitle).font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Answer mode: \(current.shortTitle)")
    }

    private func cardMenu(_ card: Card) -> some View {
        Menu {
            Button { duplicate(card) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Menu("Move to Section") {
                Button("None") { move(card, to: "") }.disabled(card.section.isEmpty)
                if !deck.sectionOrder.isEmpty { Divider() }
                ForEach(deck.sectionOrder, id: \.self) { name in
                    Button(name) { move(card, to: name) }.disabled(card.section == name)
                }
            }
            .disabled(deck.sectionOrder.isEmpty && card.section.isEmpty)
            Divider()
            Button(role: .destructive) { delete(card) } label: { Label("Delete Card", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Card options")
    }

    // MARK: Hero card

    private func heroArea(_ card: Card) -> some View {
        VStack(spacing: 14) {
            EditableStudyCard(
                id: card.id,
                front: frontBinding(card),
                back: backBinding(card),
                showingBack: $showingBack,
                mode: card.resolvedAnswerMode(deckDefault: deck.defaultAnswerMode),
                backLabel: deck.backLabel,
                section: card.section.isEmpty ? nil : card.section,
                accent: accent,
                focus: $cardFocus
            )
            .id(card.id)   // fresh per card, so its onAppear (auto-edit-if-empty) fires on each switch
            // Same framing as the study card: a 1.25 landscape card that fills the space, centered.
            .aspectRatio(1.25, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Spacing.xl)

            // Elaboration shows on the back (mirroring study) — and always for cloze, which has no back
            // face to flip to, so its "why" would otherwise be unreachable/uneditable in the gallery.
            if showingBack || card.isClozeMode {
                elaborationField(card)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showingBack)
    }

    /// A quiet elaboration field below the card — the "why / worked example / source" shown under the
    /// answer in study. Part of the card; kept slim so the card stays the hero.
    private func elaborationField(_ card: Card) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 7)
            TextField("Add an elaboration — a “why”, an example, or a source (optional)",
                      text: extraBinding(card), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typography.callout)
                .lineLimit(1...3)
                .focused($cardFocus, equals: .elaboration(card.id))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .fieldBox()
        }
    }

    private var emptyHero: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.slash").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No cards yet").font(Typography.title)
            Button { addCard() } label: { Label("Add a Card", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    stripContent
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .onChange(of: selectedID) { _, id in
                    withAnimation(.snappy) {
                        if let id { proxy.scrollTo(id, anchor: .center) }
                        else { proxy.scrollTo(Self.addTileID, anchor: .center) }
                    }
                }
            }
        }
        .frame(height: 140)
        .background(Theme.groupedBackground)
    }

    private var stripContent: some View {
        HStack(spacing: 12) {
            ForEach(orderedCards) { card in thumb(card) }
            GalleryAddTile(accent: accent) { addCard() }
                .id(Self.addTileID)
        }
    }

    private func thumb(_ card: Card) -> some View {
        GalleryThumb(card: card, isSelected: card.id == selectedID, accent: accent,
                     mode: card.resolvedAnswerMode(deckDefault: deck.defaultAnswerMode))
            .id(card.id)
            .onTapGesture { select(card.id) }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private static let addTileID = "gallery-add-tile"

    /// Hidden Esc + ← / → shortcuts, present only while NOT editing a face — so a focused card editor keeps
    /// Esc and the arrows for itself. ← / → scrub the filmstrip; **Esc closes the gallery** — the *second*
    /// stage of the two-stage Esc (the first stage, committing a face edit, is handled at the text view by
    /// `EscCommandDelegate`). It fires while resting — when nothing is first responder — because
    /// `.keyboardShortcut` registers a window-wide key equivalent, unlike `.onExitCommand`, which only
    /// receives the cancel command when its view is in the focused responder chain (hence the beep before).
    @ViewBuilder private var navigationKeys: some View {
        if !isEditingText {
            Group {
                Button("") { close() }.keyboardShortcut(.cancelAction)
                Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    /// ⌘N adds a fresh card from the keyboard (committing any in-progress edit first), mirroring the "+"
    /// tile. Always available — unlike ← / →, it's useful while editing too.
    private var addCardShortcut: some View {
        Button("", action: addCard)
            .keyboardShortcut("n", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    // MARK: Selection / navigation

    private func openInitial() {
        if let initialCardID, orderedCards.contains(where: { $0.id == initialCardID }) {
            selectedID = initialCardID
        } else if !didAutoOpen && initialCardID == nil {
            didAutoOpen = true
            addCard()   // "New Card": land on a fresh card ready to type
        } else {
            selectedID = selectedID ?? orderedCards.first?.id
        }
    }

    private func select(_ id: UUID?) {
        cardFocus = nil   // back to "browse" so the arrow keys move the strip
        withAnimation(.snappy) { selectedID = id }
    }

    private func step(_ delta: Int) {
        let cards = orderedCards
        guard !cards.isEmpty else { return }
        let current = cards.firstIndex { $0.id == selectedID } ?? 0
        let next = max(0, min(cards.count - 1, current + delta))
        if cards[next].id != selectedID { select(cards[next].id) }
    }

    // MARK: Mutations (live — edits land on the cards directly)

    private func addCard() {
        let order = deck.nextSortOrder(inSection: "")
        let card = Card(term: "", definition: "", deck: deck, section: "", sortOrder: order)
        cardFocus = nil   // commit any in-progress edit; the new (empty) card auto-enters edit on appear
        // Insert inside the animation so the new thumbnail swooshes into the strip (ForEach transition).
        withAnimation(.snappy) {
            context.insert(card)
            selectedID = card.id
            showingBack = false
        }
        persist()
    }

    private func duplicate(_ card: Card) {
        let order = deck.nextSortOrder(inSection: card.section)
        let copy = Card(term: card.term, definition: card.definition, deck: deck, section: card.section, sortOrder: order)
        copy.answerModeRaw = card.answerModeRaw
        copy.extra = card.extra
        withAnimation(.snappy) {
            context.insert(copy)
            selectedID = copy.id
        }
        persist()
    }

    private func delete(_ card: Card) {
        let cards = orderedCards
        let neighbor: UUID? = {
            guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return cards.first?.id }
            if i + 1 < cards.count { return cards[i + 1].id }
            if i - 1 >= 0 { return cards[i - 1].id }
            return nil
        }()
        cardFocus = nil
        withAnimation(.snappy) {
            context.delete(card)
            selectedID = neighbor
        }
        persist()
    }

    private func move(_ card: Card, to section: String) {
        guard card.section != section else { return }
        card.section = section
        card.sortOrder = deck.nextSortOrder(inSection: section)
        card.modifiedAt = .now
        persist()
    }

    private func close() {
        // Drop any card left completely empty — e.g. a "New Card" opened but never filled in.
        for card in deck.cardArray where isBlank(card) { context.delete(card) }
        persist()
        onClose()
    }

    private func isBlank(_ card: Card) -> Bool {
        card.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && card.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && card.extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func persist() { context.saveAndPersist(touching: deck) }

    // MARK: Live bindings onto the selected card

    private func frontBinding(_ card: Card) -> Binding<String> {
        Binding(get: { card.term }, set: { card.term = $0; card.modifiedAt = .now })
    }
    private func backBinding(_ card: Card) -> Binding<String> {
        Binding(get: { card.definition }, set: { card.definition = $0; card.modifiedAt = .now })
    }
    private func extraBinding(_ card: Card) -> Binding<String> {
        Binding(get: { card.extra }, set: { card.extra = $0; card.modifiedAt = .now })
    }
    /// Reads/writes the card's answer mode, storing empty when it matches the deck default (so an
    /// inheriting card re-encodes without an `answerMode` key) and pinning cloze explicitly.
    private func modeBinding(_ card: Card) -> Binding<AnswerMode> {
        Binding(
            get: { card.resolvedAnswerMode(deckDefault: deck.defaultAnswerMode) },
            set: { mode in
                card.answerModeRaw = mode == deck.defaultAnswerMode ? "" : mode.rawValue
                card.modifiedAt = .now
                if mode == .cloze { showingBack = false }
                persist()
            }
        )
    }
}

// MARK: - Filmstrip tiles

/// One card in the filmstrip: a mini card face showing the front (cloze shows its blanks), with an
/// accent ring + lift when it's the selected card.
private struct GalleryThumb: View {
    let card: Card
    let isSelected: Bool
    let accent: Color
    /// The card's resolved answer mode (inherits the deck default), so the badge matches the hero/study.
    let mode: AnswerMode

    private var front: String { card.isClozeMode ? Cloze.front(card.term) : card.term }
    private var label: String { front.isEmpty ? "Empty card" : front }

    var body: some View {
        caption
            .frame(width: 120, height: 86)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(border)
            .overlay(alignment: .topTrailing) { modeBadge }
            .shadow(color: .black.opacity(isSelected ? 0.14 : 0.05), radius: isSelected ? 9 : 3, y: 2)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.snappy, value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(isSelected ? "\(label), selected" : label)
    }

    private var caption: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(front.isEmpty ? Color.secondary : Color.primary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isSelected ? accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
    }

    /// A small glyph marking non-flip cards so the strip reads at a glance.
    @ViewBuilder private var modeBadge: some View {
        let symbol: String? = mode == .cloze ? "curlybraces" : (mode == .type ? "keyboard" : nil)
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
                .padding(4)
                .background(accent.opacity(0.14), in: Circle())
                .padding(5)
        }
    }
}

/// The "+" tile at the end of the strip: a dashed accent tile whose plus scales up on hover; clicking
/// it adds a fresh card (which swooshes into the strip via the ForEach insertion transition).
private struct GalleryAddTile: View {
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(hovering ? 0.18 : 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(accent.opacity(hovering ? 0.65 : 0.32),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accent)
                    .scaleEffect(hovering ? 1.22 : 1.0)
            }
            .frame(width: 120, height: 86)
            .scaleEffect(hovering ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.snappy) { self.hovering = hovering } }
        .help("Add a card (⌘N)")
        .accessibilityLabel("Add a card")
    }
}
