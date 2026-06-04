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
/// has no native placeholder, so it's drawn as an overlay. Optional external focus binding, like
/// `LabeledField`.
struct MultilineField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var minHeight: CGFloat = 96
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .focused(ifPresent: focus)
                .font(Typography.body)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)   // handles iOS; no-op on macOS TextEditor (see below)
                #if os(macOS)
                .background(HideVerticalScroller())
                #endif
                .frame(minHeight: minHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .fieldBox()
                .overlay(alignment: .topLeading) {
                    if text.isEmpty && !placeholder.isEmpty {
                        Text(placeholder)
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

#if os(macOS)
/// Hides the scroll indicator on the macOS NSScrollView backing a SwiftUI `TextEditor` —
/// `.scrollIndicators(.hidden)` has no effect on TextEditor there. Drop in as a `.background`
/// of the editor; it finds the editor's own scroll view (guarding on an NSTextView document so it
/// can't grab an outer ScrollView) and disables its scrollers.
struct HideVerticalScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.hide(from: view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.hide(from: nsView) }
    }
    private static func hide(from view: NSView) {
        guard let scrollView = textScrollView(near: view) else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller?.isHidden = true
    }
    private static func textScrollView(near view: NSView) -> NSScrollView? {
        if let scroll = view.enclosingScrollView, scroll.documentView is NSTextView { return scroll }
        var ancestor: NSView? = view.superview
        while let current = ancestor {
            if let scroll = scrollViewWithText(in: current) { return scroll }
            ancestor = current.superview
        }
        return nil
    }
    private static func scrollViewWithText(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is NSTextView { return scroll }
        for subview in view.subviews {
            if let scroll = scrollViewWithText(in: subview) { return scroll }
        }
        return nil
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
