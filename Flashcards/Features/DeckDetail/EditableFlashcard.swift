import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Which editable region of a card has focus. File-scoped (not nested in a view) so the composer and
/// the editable card can share one `@FocusState` — the composer drives focus to a specific card's
/// front/back (e.g. after "Add Card" or a paste), and a flip moves focus to the newly-shown side. The
/// gallery editor adds the per-card elaboration field to the same focus space.
enum CardEditorField: Hashable { case front(UUID), back(UUID), elaboration(UUID) }

/// The card **editor** surface — the very same elevated study card the learner sees
/// (`StudyCardBackground` + `StudyCardLabel` + `StudyCardSectionChip`, shared with `FlashcardView`),
/// but with the text editable **in place** on the card. You edit the front right on the front face;
/// tap **Flip** to turn the card and edit the back. A cloze card is a single face: you edit the
/// `{{c1::…}}` text on the card with the blanks visible. The layout is **fixed** — nothing drags,
/// resizes, or repositions; only the text is editable. This is the 1.8.0 "editable study card"
/// composer surface (see `BulkAddView`); answer mode, section, and elaboration live in the minimal
/// surround around it.
struct EditableFlashcard: View {
    let id: UUID
    @Binding var front: String
    @Binding var back: String
    /// Which face is up for a flip/type card. Owned by the parent (a composer row) so each card keeps
    /// its own flip state. Ignored for cloze (a single face).
    @Binding var showingBack: Bool
    let mode: AnswerMode
    var backLabel: String = "Definition"
    var section: String? = nil
    var accent: Color = Theme.accent
    var minHeight: CGFloat = 240
    /// Rapid-add front: a commit-on-Return field (so Return adds the next card and a delimited paste
    /// splits into rows), instead of the full multi-line editor used when editing one card.
    var rapidFront: Bool = false
    /// Called when Return is pressed in a rapid-add front (the composer adds the next card).
    var onFrontSubmit: (() -> Void)? = nil

    var focus: FocusState<CardEditorField?>.Binding

    private var isCloze: Bool { mode == .cloze }
    /// The word for the answer side — "Answer" for a type-in card, otherwise the deck's back label.
    private var backWord: String { mode == .type ? "Answer" : (backLabel.isEmpty ? "Back" : backLabel) }

    var body: some View {
        Group {
            if isCloze {
                clozeFace
            } else {
                ZStack {
                    if showingBack {
                        face(side: .back).transition(.cardFlip)
                    } else {
                        face(side: .front).transition(.cardFlip)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showingBack)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    // MARK: Flip/type faces

    private enum Side { case front, back }

    @ViewBuilder private func face(side: Side) -> some View {
        let isBack = side == .back
        ZStack {
            StudyCardBackground()
                // Click anywhere on the card surface to start editing the side that's showing.
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .onTapGesture { focus.wrappedValue = isBack ? .back(id) : .front(id) }

            VStack(spacing: 12) {
                if isBack { StudyCardLabel(label: backWord, accent: accent) }
                if isBack {
                    CardEditorText(text: $back, placeholder: "Type the \(backWord.lowercased())",
                                   centered: true, baseSize: 22, field: .back(id), focus: focus)
                } else {
                    CardEditorText(text: $front, placeholder: "Type the front",
                                   centered: true, baseSize: 24, field: .front(id), focus: focus,
                                   onSubmit: onFrontSubmit, singleLineCommits: rapidFront)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 38)      // clears the section chip
            .padding(.bottom, 44)   // clears the flip pill
        }
        .overlay(alignment: .top) { StudyCardSectionChip(section: section, accent: accent) }
        .overlay(alignment: .bottom) { flipPill(isBack: isBack) }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    /// The flip affordance, pinned to the bottom of the card like the study "tap to flip" hint — but a
    /// real control here, since the card face itself is a text field. Turns the card to the other side
    /// and moves focus there, so you can keep typing.
    private func flipPill(isBack: Bool) -> some View {
        Button {
            showingBack.toggle()
            focus.wrappedValue = isBack ? .front(id) : .back(id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.circlepath")
                Text(isBack ? "Front" : backWord)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
        .accessibilityLabel(isBack ? "Flip to front" : "Flip to \(backWord.lowercased())")
    }

    // MARK: Cloze face

    /// Cloze is one face: the `{{c1::…}}` text is edited right on the card, blanks visible. No flip — a
    /// fill-in-the-blank has no separate back. A live "in study" preview sits beneath it (in the composer).
    private var clozeFace: some View {
        ZStack {
            StudyCardBackground()
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .onTapGesture { focus.wrappedValue = .front(id) }

            VStack(spacing: 12) {
                StudyCardLabel(label: "Cloze", accent: accent)
                CardEditorText(text: $front, placeholder: "The {{c1::sun}} is a star.",
                               centered: false, baseSize: 20, field: .front(id), focus: focus)
            }
            .padding(.horizontal, 26)
            .padding(.top, 38)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .top) { StudyCardSectionChip(section: section, accent: accent) }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

// MARK: - Editable text region

/// One editable text region living on a card face: the card's text, in place, with a native-style
/// placeholder that clears on focus. Transparent so the card surface shows through; centered for a
/// term/definition, leading for cloze. In rapid-add the front uses a commit-on-Return field (Return
/// adds the next card); everywhere else it's a full multi-line editor (Markdown + LaTeX).
private struct CardEditorText: View {
    @Binding var text: String
    var placeholder: String
    var centered: Bool
    var baseSize: CGFloat
    let field: CardEditorField
    var focus: FocusState<CardEditorField?>.Binding
    var onSubmit: (() -> Void)? = nil
    var singleLineCommits: Bool = false

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        editor
            .font(.system(size: baseSize, weight: .semibold, design: .rounded))
            .multilineTextAlignment(centered ? .center : .leading)
            .foregroundStyle(.primary)
            .tint(.accentColor)
            // Size to the text (not the whole card) so a short term sits vertically centered like the
            // study card, and the card grows as the text does — never an internal scroll.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .overlay(alignment: centered ? .top : .topLeading) {
                if text.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(.system(size: baseSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(centered ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder private var editor: some View {
        if singleLineCommits {
            // Rapid-add front: a vertical-axis field that COMMITS on Return (macOS) — so Return adds the
            // next card and a multi-line paste flows to the composer's paste-splitter — wrapping rather
            // than scrolling sideways for a long term.
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused(focus, equals: field)
                .onSubmit { onSubmit?() }
        } else {
            // A multi-line editor that grows with its content (the `.fixedSize` above pins it to the
            // text height) so the card centers the text and expands as you type.
            TextEditor(text: $text)
                .focused(focus, equals: field)
                .scrollContentBackground(.hidden)
                .frame(minHeight: baseSize * 1.3)
                #if os(macOS)
                .background(CardEditorConfigurator(centered: centered))   // transparent + alignment
                #endif
        }
    }
}

#if os(macOS)
/// Tunes the macOS `TextEditor`'s backing NSTextView so it reads as text *on the card*: a transparent
/// background (the card surface shows through) and centered or natural alignment to match the face. No
/// scroller — the editor is content-sized (it grows with the text; the composer page scrolls if needed),
/// so a scrollbar would only ever be a stray artifact. Mirrors `TextEditorConfigurator` (reusing its
/// geometry-targeted scroll-view lookup) but drops the field-box background.
private struct CardEditorConfigurator: NSViewRepresentable {
    var centered: Bool

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.centered = centered; nsView.configure() }

    final class Probe: NSView {
        var centered = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        override func layout() { super.layout(); configure() }

        func configure() {
            guard let scroll = TextEditorConfigurator.textScrollView(behind: self) else { return }
            scroll.drawsBackground = false
            // The editor is content-sized, so there's nothing to scroll; a native fading overlay
            // scroller (autohiding) stays out of the way and matches the app's other text editors.
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.hasHorizontalScroller = false
            if let textView = scroll.documentView as? NSTextView {
                textView.drawsBackground = false
                // No vertical inset: the editor is content-sized, so any extra inset would push the
                // document taller than the frame and leave a permanent sliver to scroll (a stray knob).
                textView.textContainerInset = NSSize(width: 0, height: 0)
                textView.textContainer?.lineFragmentPadding = 5
                let alignment: NSTextAlignment = centered ? .center : .natural
                textView.alignment = alignment
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                textView.defaultParagraphStyle = style
                textView.typingAttributes[.paragraphStyle] = style
            }
        }
    }
}
#endif

// MARK: - Flip transition

/// A card-flip transition for the editable face: the outgoing side rotates edge-on as the incoming side
/// rotates in, with a fade — so swapping front↔back reads like flipping the study card. Unlike a literal
/// 3D rotation held at rest, a transition leaves the settled face with NO residual transform, so the
/// live text editor stays pristinely interactive (a 3D-transformed NSTextView mis-places its caret).
private struct FlipFace: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

extension AnyTransition {
    static var cardFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipFace(angle: -90), identity: FlipFace(angle: 0)),
            removal: .modifier(active: FlipFace(angle: 90), identity: FlipFace(angle: 0))
        )
        .combined(with: .opacity)
    }
}
