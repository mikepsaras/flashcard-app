#if os(macOS)
import SwiftUI
import AppKit

/// Wires a native double-click action onto the `NSTableView` that backs a SwiftUI `List`, so a
/// double-click can open a row WITHOUT a SwiftUI tap gesture — which would disable the List's
/// native drag-reorder AND click-to-select (FB7367473). A native table supports drag and
/// `doubleAction` simultaneously, so this coexists with both.
///
/// Experimental: it reaches into AppKit internals SwiftUI doesn't promise are stable, so it may
/// need revisiting on OS updates. Drop it in as a `.background` of the List; `onDoubleClick` is
/// called with the clicked row index, which maps to the List's (flattened) row order.
struct TableDoubleClickHandler: NSViewRepresentable {
    var onDoubleClick: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDoubleClick: onDoubleClick) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the closure fresh (it captures current rows) and re-assert the action in case
        // SwiftUI rebuilt the table or cleared our target/doubleAction.
        context.coordinator.onDoubleClick = onDoubleClick
        DispatchQueue.main.async { context.coordinator.attach(from: nsView) }
    }

    final class Coordinator: NSObject {
        var onDoubleClick: (Int) -> Void
        weak var tableView: NSTableView?

        init(onDoubleClick: @escaping (Int) -> Void) { self.onDoubleClick = onDoubleClick }

        func attach(from view: NSView) {
            guard let table = tableView ?? Self.enclosingTableView(of: view) else { return }
            tableView = table
            table.target = self          // NSControl.target is weak; SwiftUI retains this Coordinator
            table.doubleAction = #selector(handleDoubleClick)
        }

        @objc private func handleDoubleClick() {
            guard let row = tableView?.clickedRow, row >= 0 else { return }
            onDoubleClick(row)
        }

        /// Finds the table backing the List this view sits in: the nearest enclosing scroll view's
        /// document view, else the nearest table in an expanding ancestor search (which finds THIS
        /// list's table before the sidebar's, since that lives higher up the hierarchy).
        static func enclosingTableView(of view: NSView) -> NSTableView? {
            if let table = view.enclosingScrollView?.documentView as? NSTableView { return table }
            var ancestor: NSView? = view.superview
            while let current = ancestor {
                if let table = firstTableView(in: current) { return table }
                ancestor = current.superview
            }
            return nil
        }

        private static func firstTableView(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for subview in view.subviews {
                if let table = firstTableView(in: subview) { return table }
            }
            return nil
        }
    }
}
#endif
