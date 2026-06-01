import SwiftUI

#if os(macOS)
import AppKit

/// Renders SwiftUI views to PNG files on disk so the design can be inspected
/// without Screen Recording permission or a running app/simulator.
/// Output lands in /tmp/flashcards_snapshots/<name>.png.
enum Snapshot {
    static let directory = "/tmp/flashcards_snapshots"

    enum Failure: Error { case renderFailed }

    @MainActor
    static func write(
        _ view: some View,
        size: CGSize,
        scale: CGFloat = 2,
        name: String,
        directory: String = Snapshot.directory
    ) throws {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        guard
            let nsImage = renderer.nsImage,
            let tiff = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { throw Failure.renderFailed }

        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
