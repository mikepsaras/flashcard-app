#if os(macOS)
import SwiftUI
import AppKit

/// During study, makes the window's title bar transparent + full-size-content so the
/// session fills the window edge-to-edge. When *not* studying it restores SwiftUI's
/// original sidebar-app title bar setup (captured once) rather than forcing values —
/// forcing them broke the default full-height sidebar (traffic lights over the sidebar).
struct WindowConfigurator: NSViewRepresentable {
    let fullSizeContent: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var original: (transparent: Bool, fullSize: Bool, titleVisibility: NSWindow.TitleVisibility)?
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in apply(to: view?.window, context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in apply(to: nsView?.window, context.coordinator) }
    }

    private func apply(to window: NSWindow?, _ coordinator: Coordinator) {
        guard let window else { return }

        // Enforce the window's minimum size here, at the AppKit level — NOT via a SwiftUI
        // `.frame(minWidth:…)` wrapped around the NavigationSplitView. That frame breaks the
        // sidebar reveal animation (the column snaps and the toolbar/search field re-lays-out
        // mid-animation). `window.minSize` is decoupled from the split view's layout.
        window.minSize = NSSize(width: 900, height: 680)

        if coordinator.original == nil {
            coordinator.original = (
                window.titlebarAppearsTransparent,
                window.styleMask.contains(.fullSizeContentView),
                window.titleVisibility
            )
        }

        if fullSizeContent {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        } else if let original = coordinator.original {
            window.titlebarAppearsTransparent = original.transparent
            window.titleVisibility = original.titleVisibility
            if original.fullSize {
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.styleMask.remove(.fullSizeContentView)
            }
        }

        // Hide the traffic lights for a fully immersive study view; restore on exit.
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = fullSizeContent
        }
    }
}
#endif
