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
    }
}
#endif
