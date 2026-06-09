import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The gallery's hero card: at rest it renders **exactly** like the study card (`FlashcardView`'s shared
/// `StudyCardBackground` + `StudyCardText` — same scaled, shrink-to-fit, Markdown/LaTeX text, section
/// chip, and 3D flip). Click a face to **edit it in place** (the rendered text swaps for a transparent
/// editor over the same surface); click away / Tab / ⌘↵ commits and it re-renders. Flipping is the
/// **button only** (⌘↵) — never click or Space — so click can edit and Space/Return type freely. Because
/// the editor only ever shows on the *resting, un-rotated* face (we commit before flipping), the real 3D
/// rotation is safe (a rotated NSTextView mis-places its caret).
struct EditableStudyCard: View {
    let id: UUID
    @Binding var front: String
    @Binding var back: String
    @Binding var showingBack: Bool
    let mode: AnswerMode
    var backLabel: String = "Definition"
    var section: String? = nil
    var accent: Color = Theme.accent
    var focus: FocusState<CardEditorField?>.Binding

    @ScaledMetric(relativeTo: .largeTitle) private var termSize: CGFloat = 40

    private enum Side { case front, back }
    private var isCloze: Bool { mode == .cloze }
    private var backWord: String { mode == .type ? "Answer" : (backLabel.isEmpty ? "Back" : backLabel) }

    /// Which face is being edited (nil = resting/rendered). Drives the editor's existence EXPLICITLY:
    /// we mount the editor first, then focus it next-runloop. Setting `@FocusState` before the field is
    /// in the tree just reverts (focus bootstrapping), and a TextEditor inside the 3D-rotated card can't
    /// take focus at all — so editing renders the active face FLAT.
    @State private var editingSide: Side?

    private func field(_ side: Side) -> CardEditorField { side == .back ? .back(id) : .front(id) }

    /// Enter edit on a face: mount its editor, then focus it on the next runloop (once it's in the tree).
    private func beginEditing(_ side: Side) {
        guard editingSide != side else { return }
        editingSide = side
        let target = field(side)
        DispatchQueue.main.async { focus.wrappedValue = target }
    }

    var body: some View {
        GeometryReader { geo in
            let fontSize = studyCardFontSize(width: geo.size.width, floor: termSize)
            Group {
                if isCloze {
                    clozeFace(fontSize: fontSize)
                } else if let side = editingSide {
                    // Editing: the active face FLAT (no 3D layer) so its NSTextView can take focus. It
                    // looks identical to the resting face, so the swap is seamless.
                    face(side, fontSize: fontSize)
                        .background(flipShortcut)
                } else {
                    flipCard(fontSize: fontSize)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .contain)
        // Exit edit when focus leaves the card (Tab, Esc, clicking a thumbnail, etc.) → re-render.
        .onChange(of: focus.wrappedValue) { _, value in if value == nil { editingSide = nil } }
        // A fresh, empty card opens ready to type; an existing card rests rendered until you click it.
        .onAppear { if !isCloze, front.isEmpty, back.isEmpty { beginEditing(.front) } }
    }

    /// The resting / flipping card: two faces in a real 3D rotation (like `FlashcardView`), rendered
    /// (never editing — editing swaps to the flat face above). Tapping it edits the showing face.
    private func flipCard(fontSize: CGFloat) -> some View {
        ZStack {
            face(.front, fontSize: fontSize).opacity(showingBack ? 0 : 1)
            face(.back, fontSize: fontSize)
                .opacity(showingBack ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(showingBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.cardFlip, value: showingBack)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture { beginEditing(showingBack ? .back : .front) }
        .background(flipShortcut)   // ⌘↵ flips even while editing (commits first)
    }

    /// A comfortable editing size — capped below the (often huge) rendered size so typing isn't unwieldy.
    /// On commit the text re-renders at the full study-scaled size (the expected source↔preview shift).
    private func editSize(_ base: CGFloat) -> CGFloat { min(base, 34) }

    // MARK: Flip/type faces

    @ViewBuilder private func face(_ side: Side, fontSize: CGFloat) -> some View {
        let isBack = side == .back
        let field: CardEditorField = isBack ? .back(id) : .front(id)
        let editing = editingSide == side
        let placeholder = isBack ? "Type the \(backWord.lowercased())" : "Type the front"
        ZStack {
            StudyCardBackground()
            VStack(spacing: 14) {
                if isBack { StudyCardLabel(label: backWord, accent: accent) }
                content(text: isBack ? $back : $front, rendered: isBack ? back : front,
                        editing: editing, field: field, fontSize: fontSize, placeholder: placeholder)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { StudyCardSectionChip(section: section, accent: accent) }
        .overlay(alignment: .bottom) { flipButton(isBack: isBack) }
    }

    // MARK: Cloze (single face — the `{{c1::…}}` text; masked like study at rest, raw while editing)

    private func clozeFace(fontSize: CGFloat) -> some View {
        let field: CardEditorField = .front(id)
        // Only the front is editable for cloze, so gate on `.front` (not `!= nil`): a stale `.back`
        // left over from switching a flip card to cloze mid-back-edit must NOT render the raw-markup
        // editing state with no caret. Mounting still keys off `editingSide`, so focus bootstrapping holds.
        let editing = editingSide == .front
        return ZStack {
            StudyCardBackground()
            VStack(spacing: 14) {
                StudyCardLabel(label: "Cloze", accent: accent)
                clozeContent(editing: editing, field: field, fontSize: fontSize)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture { beginEditing(.front) }
        .overlay(alignment: .top) { StudyCardSectionChip(section: section, accent: accent) }
    }

    @ViewBuilder private func clozeContent(editing: Bool, field: CardEditorField, fontSize: CGFloat) -> some View {
        if editing {
            GalleryCardEditor(text: $front, field: field, focus: focus, fontSize: editSize(fontSize))
        } else if front.isEmpty {
            placeholderText("The {{c1::sun}} is a star.", fontSize: fontSize)
        } else {
            // Masked just like study (the active deletions become […]); edit to see/change the answer.
            StudyCardText(text: Cloze.front(front), fontSize: fontSize)
        }
    }

    // MARK: Face content (rendered ↔ editing)

    @ViewBuilder private func content(text: Binding<String>, rendered: String, editing: Bool,
                                      field: CardEditorField, fontSize: CGFloat, placeholder: String) -> some View {
        if editing {
            GalleryCardEditor(text: text, field: field, focus: focus, fontSize: editSize(fontSize))
        } else if rendered.isEmpty {
            placeholderText(placeholder, fontSize: fontSize)
        } else {
            StudyCardText(text: rendered, fontSize: fontSize)
        }
    }

    /// The faint "what goes here" cue shown on an empty face at rest, in the card's text style.
    private func placeholderText(_ text: String, fontSize: CGFloat) -> some View {
        Text(text)
            .font(.system(size: editSize(fontSize), weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: Flip controls

    /// Flip = button only (with ⌘↵). Commits the current edit (clears focus → re-renders) and turns the
    /// card; clearing focus first means the editor is gone before the 3D rotation runs.
    private func flip() {
        editingSide = nil
        focus.wrappedValue = nil
        // Defer the toggle one runloop: exiting edit swaps the flat face back to the rotating card, and
        // we want that card mounted (at the current side) BEFORE it animates — otherwise it would just
        // appear already-flipped. With the deferral the rotation animates whether or not we were editing.
        DispatchQueue.main.async {
            withAnimation(.cardFlip) { showingBack.toggle() }
        }
    }

    private func flipButton(isBack: Bool) -> some View {
        CardFlipPill(label: isBack ? "Front" : backWord, accent: accent, showShortcut: true, action: flip)
            .padding(.bottom, 16)
            .accessibilityLabel(isBack ? "Flip to front" : "Flip to \(backWord.lowercased())")
    }

    /// A zero-size hidden button so ⌘↵ flips from anywhere — including while a face editor has focus.
    private var flipShortcut: some View {
        Button("", action: flip)
            .keyboardShortcut(.return, modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

// MARK: - In-place face editor (fills the face, transparent, centered, scrolls if long)

/// The editable text on a card face: a transparent, centered `TextEditor` filling the face, scrolling
/// if the content outgrows the (fixed) card. The card's own placeholder/rendered text handles the empty
/// and resting states, so this is only ever shown focused.
private struct GalleryCardEditor: View {
    @Binding var text: String
    let field: CardEditorField
    var focus: FocusState<CardEditorField?>.Binding
    var fontSize: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .focused(focus, equals: field)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .scrollContentBackground(.hidden)
            .tint(.accentColor)
            .foregroundStyle(.primary)
            // Content-sized (not filling) so a short term stays vertically centered like the rendered
            // text — only the font size shifts on commit, never the position.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            #if os(macOS)
            .background(GalleryEditorConfigurator())   // transparent NSTextView, centered
            #endif
    }
}

#if os(macOS)
/// Makes the face `TextEditor` read as text on the card: transparent background and centered alignment,
/// no scroller (the editor is content-sized, so it never scrolls — and a zeroed text inset avoids the
/// stray overlay-scroller knob). Reuses `TextEditorConfigurator`'s geometry-targeted lookup.
private struct GalleryEditorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.configure() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        override func layout() { super.layout(); configure() }

        func configure() {
            guard let scroll = TextEditorConfigurator.textScrollView(behind: self) else { return }
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = false   // content-sized editor never scrolls — no stray knob
            scroll.hasHorizontalScroller = false
            if let textView = scroll.documentView as? NSTextView {
                textView.drawsBackground = false
                textView.textContainerInset = NSSize(width: 0, height: 0)
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                textView.alignment = .center
                textView.defaultParagraphStyle = style
                textView.typingAttributes[.paragraphStyle] = style
            }
        }
    }
}
#endif
