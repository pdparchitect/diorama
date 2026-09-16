import AppKit
import Testing
@testable import Diorama

@Suite @MainActor
struct StageWindowInteractionTests {
    @Test func movingAndResizingReleaseCaptureSynchronously() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = StageNSView(frame: .zero)
        window.contentView = view
        var releases = 0
        view.onWindowInteraction = { releases += 1 }

        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: window)
        #expect(releases == 1)
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: window)
        #expect(releases == 2)

        // Detached views must stop reacting to the old window's gestures.
        view.removeFromSuperview()
        NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: window)
        #expect(releases == 2)
    }
}
