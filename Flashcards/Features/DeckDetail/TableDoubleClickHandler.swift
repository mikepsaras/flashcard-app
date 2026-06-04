#if os(macOS)
import SwiftUI
import AppKit

/// Bridges to the `NSTableView` backing a SwiftUI `List` to add two native behaviors a SwiftUI row
/// gesture can't provide without disabling the List's drag-reorder + click-select (FB7367473):
/// a **double-click** to open a row, and a **drag-began** signal (a left-drag inside the table) used
/// to clear a stale selection while a card is being dragged. A native table does both alongside its
/// own drag/selection. Experimental AppKit introspection — drop in as a `.background` of the List.
struct TableDoubleClickHandler: NSViewRepresentable {
    var onDoubleClick: (Int) -> Void
    var onRowDrag: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onDoubleClick: onDoubleClick, onRowDrag: onRowDrag) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the closures fresh (they capture current rows/selection) and re-assert the action in
        // case SwiftUI rebuilt the table or cleared our target/doubleAction.
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.onRowDrag = onRowDrag
        DispatchQueue.main.async { context.coordinator.attach(from: nsView) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject {
        var onDoubleClick: (Int) -> Void
        var onRowDrag: (() -> Void)?
        weak var tableView: NSTableView?
        private var dragMonitor: Any?

        init(onDoubleClick: @escaping (Int) -> Void, onRowDrag: (() -> Void)?) {
            self.onDoubleClick = onDoubleClick
            self.onRowDrag = onRowDrag
        }

        func attach(from view: NSView) {
            guard let table = tableView ?? Self.enclosingTableView(of: view) else { return }
            tableView = table
            table.target = self          // NSControl.target is weak; SwiftUI retains this Coordinator
            table.doubleAction = #selector(handleDoubleClick)
            installDragMonitorIfNeeded()
        }

        /// A left-drag inside the table is a row reorder; report it so the view can clear any
        /// selected-but-not-dragged card (which otherwise flickers as the drag passes a header).
        private func installDragMonitorIfNeeded() {
            guard dragMonitor == nil else { return }
            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                guard let self, let table = self.tableView, event.window === table.window else { return event }
                let point = table.convert(event.locationInWindow, from: nil)
                if table.bounds.contains(point) { self.onRowDrag?() }
                return event   // don't consume — the drag must proceed normally
            }
        }

        func teardown() {
            if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
            dragMonitor = nil
        }

        deinit { teardown() }

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
