#if os(macOS)
import AppKit
import SwiftData

/// macOS app delegate: guarantees queued background deck writes land before the process exits.
/// SwiftUI's `scenePhase` is unreliable at quit (the window can go away without an `.inactive`
/// tick), so termination is the one hook that can both enqueue a final persist — covering e.g.
/// ⌘Q mid-study, whose grades otherwise persist only on session finish — and wait for the
/// persist pipeline to go quiet.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Finder double-click / drag-onto-Dock-icon delivery. On macOS, `onOpenURL` does NOT fire
    /// for document opens (verified live) — only this delegate hook sees them. The WindowGroup's
    /// `handlesExternalEvents(matching: ["*"])` stops SwiftUI from ALSO spawning a fresh window
    /// for the event. (iOS delivers through `onOpenURL`, which IS reliable there.)
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !DeckStore.isHostingTests else { return }
        AppActions.shared.requestOpen(urls: urls.filter { DeckStore.isDeckFile($0) })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The test host shares the app's bundle id + library bookmark; a quit-time persist from
        // it would prune the user's real library against the tests' empty context.
        guard !DeckStore.isHostingTests else { return .terminateNow }
        if let context = DeckStore.shared.liveContext {
            DeckStore.shared.persist(context)
        }
        Task { @MainActor in
            // Wait for queued writes, but never hold the quit hostage — 5s dwarfs any real flush.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await DeckStore.shared.flush() }
                group.addTask { try? await Task.sleep(for: .seconds(5)) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
