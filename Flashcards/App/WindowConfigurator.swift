#if os(macOS)
import SwiftUI
import AppKit

/// Toggles the host window between a normal title bar and a transparent,
/// full-size-content title bar (content extends under it, traffic lights overlaid).
/// Used so the study session can fill the window edge-to-edge.
struct WindowConfigurator: NSViewRepresentable {
    let fullSizeContent: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in apply(to: view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in apply(to: nsView?.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = fullSizeContent
        window.titleVisibility = fullSizeContent ? .hidden : .visible
        if fullSizeContent {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }
    }
}
#endif
