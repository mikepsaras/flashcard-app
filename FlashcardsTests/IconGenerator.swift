import SwiftUI
import Testing
@testable import Flashcards

#if os(macOS)

/// Dev tool (not a behavioural test): renders the app-icon artwork at every needed pixel size into
/// /tmp/flashcards_icons. The icon-build script then copies the PNGs into the asset catalog. Re-run
/// after changing `AppIconArtwork`. (The .cards document icon is left to macOS's default.)
@MainActor
@Suite struct IconGenerator {
    static let out = "/tmp/flashcards_icons"

    @Test func generate() throws {
        // macOS app icon — squircle, transparent margin.
        for n in [16, 32, 64, 128, 256, 512, 1024] {
            try Snapshot.write(AppIconArtwork(squircle: true), size: CGSize(width: n, height: n),
                               scale: 1, name: "icon_mac_\(n)", directory: Self.out)
        }
        // iOS app icon — full-bleed (the system masks it).
        try Snapshot.write(AppIconArtwork(squircle: false), size: CGSize(width: 1024, height: 1024),
                           scale: 1, name: "icon_ios_1024", directory: Self.out)
    }
}
#endif
