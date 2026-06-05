import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A labeled editor field: a small caption above the field, with the text sitting in a
/// clean rounded box (a step lighter than the page). The placeholder is native — it stays
/// visible until you type. Supports a multi-line box via `lines` (a tidy text area), and an
/// optional external focus binding so a form can drive focus (e.g. refocus after "Add & New").
struct LabeledField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int>? = nil
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            field
                .textFieldStyle(.plain)
                .focused(ifPresent: focus)
                .font(Typography.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldBox()
        }
    }

    @ViewBuilder private var field: some View {
        if let lines {
            TextField(placeholder, text: $text, axis: axis).lineLimit(lines)
        } else {
            TextField(placeholder, text: $text, axis: axis)
        }
    }
}

extension View {
    /// The editor field-box chrome — a rounded surface a step above the grouped page,
    /// subtly bordered. Shared by `LabeledField`, the editor toggle rows, and the AI form
    /// so every input box matches. Apply your own inner padding before this.
    func fieldBox(cornerRadius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.fieldSurface))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
    }

    /// Applies `.focused` only when a binding is supplied, so callers that don't manage focus
    /// can omit it.
    @ViewBuilder func focused(ifPresent binding: FocusState<Bool>.Binding?) -> some View {
        if let binding { focused(binding) } else { self }
    }
}

/// A labeled multi-line text box backed by `TextEditor`, so Return reliably inserts a newline — a
/// vertical-axis `TextField` commits instead on macOS, which blocks multi-line entry. `TextEditor`
/// has no native placeholder, so it's drawn as an overlay — and hidden once the field is focused (or
/// has text), so an active field is never cluttered by its hint. `autofocus` focuses it on appear;
/// bump `refocus` from the parent to re-focus it (e.g. after "Add & Add Another").
struct MultilineField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var minHeight: CGFloat = 96
    var autofocus: Bool = false
    var refocus: Int = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .focused($isFocused)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                #if os(macOS)
                .background(TextEditorConfigurator())   // overlay scroller (fades) + zeroed text inset
                #endif
                .frame(minHeight: minHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .fieldBox()
                .overlay(alignment: .topLeading) {
                    // Native-style placeholder: gone as soon as you focus the field or type. It sits at
                    // (13, 14) — 8pt h-padding + 5pt line-fragment = 13; 6pt v-padding + 8pt text inset
                    // = 14 — and the editor's text is inset to the SAME spot, so the two coincide.
                    if text.isEmpty && !isFocused && !placeholder.isEmpty {
                        Text(placeholder)
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear { if autofocus { isFocused = true } }
        .onChange(of: refocus) { _, _ in isFocused = true }
    }
}

#if os(macOS)
/// Tunes the macOS `TextEditor`'s backing NSTextView / scroll view, which SwiftUI doesn't expose:
/// (1) a native **overlay** scroller that appears only while scrolling and fades out (instead of the
/// persistent legacy scrollbar a mouse user gets by default; `.scrollIndicators(.hidden)` has no
/// effect on TextEditor), and (2) an **8pt top text-container inset** (matching iOS's UITextView
/// default) so the cursor / typed text rests where the placeholder sits, not jammed against the top.
/// Drop in as a `.background` of the editor; it finds the editor's own scroll view (guarding on an
/// NSTextView document so it can't grab an outer ScrollView).
struct TextEditorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.configure() }

    /// Configures during the layout pass (before drawing) and on window-entry, rather than a
    /// runloop-later `DispatchQueue.main.async` — which let the unstyled scroller / inset paint for
    /// one frame first (a brief flicker on open).
    final class Probe: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        override func layout() { super.layout(); configure() }

        func configure() {
            guard let scroll = TextEditorConfigurator.textScrollView(behind: self) else { return }
            scroll.scrollerStyle = .overlay      // thin overlay that fades, regardless of mouse/trackpad
            scroll.autohidesScrollers = true     // …and only shows while actively scrolling
            scroll.hasVerticalScroller = true
            scroll.verticalScroller?.isHidden = false
            scroll.hasHorizontalScroller = false
            // Give the text an 8pt top inset (what iOS's UITextView has by default) so the cursor /
            // typed text rests at the placeholder's resting spot (6pt v-padding + 8 = 14) instead of
            // jammed against the top. 5pt line-fragment padding sets the 13pt the placeholder matches.
            if let textView = scroll.documentView as? NSTextView {
                textView.textContainerInset = NSSize(width: 0, height: 8)
                textView.textContainer?.lineFragmentPadding = 5
            }
        }
    }

    /// This editor's OWN scroll view: among the window's text scroll views, the one whose frame
    /// contains this view's center. A plain ancestor/DFS search returns the first match, which
    /// mis-targets a sibling field's editor when several share a container. Geometry pins it to the
    /// right editor.
    static func textScrollView(behind view: NSView) -> NSScrollView? {
        guard let content = view.window?.contentView, view.bounds.width > 0 else { return nil }
        let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return textScrollViews(in: content).first { $0.convert($0.bounds, to: nil).contains(center) }
    }
    private static func textScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scroll = view as? NSScrollView, scroll.documentView is NSTextView { result.append(scroll) }
        for subview in view.subviews { result.append(contentsOf: textScrollViews(in: subview)) }
        return result
    }
}
#endif

#Preview {
    VStack(spacing: 22) {
        LabeledField(label: "Name", placeholder: "Deck name", text: .constant(""))
        LabeledField(label: "Definition", placeholder: "Back of the card", text: .constant(""), axis: .vertical, lines: 3...10)
    }
    .padding(24)
    .frame(width: 380)
    .background(Theme.groupedBackground)
}
