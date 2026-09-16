import AppKit
import DioramaCore

/// Installs the event tap that fences the pointer and routes it onto the virtual display while it is captured.
///
/// The tap sits at the HID level so an event's location can still be rewritten before the window server delivers it.
/// Everything here runs on the main thread: the tap's run-loop source is attached to the main run loop, and the model
/// only touches the bridge from the main actor. The class is nonisolated so the C callback can reach it without an actor hop.
final class InputBridge: @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var fence = CursorFence()
    private var wallpaperClicks = WallpaperClickGuard()

    /// Window number of the stage window, used to make sure the stage is actually the topmost window under the pointer.
    var stageWindowNumber = 0
    var onTransition: (@MainActor (CursorFence.Transition) -> Void)?
    var onHotkey: (@MainActor (Hotkey) -> Void)?

    var isInstalled: Bool { tap != nil }
    var isCaptured: Bool { fence.isCaptured }

    private static let pointerEvents: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel
    ]

    /// Creates the tap. Returns false when the process is not trusted for Accessibility.
    @discardableResult
    func install() -> Bool {
        if tap != nil { return true }
        var mask: CGEventMask = 0
        for type in Self.pointerEvents + [.keyDown] { mask |= 1 << type.rawValue }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let bridge = Unmanaged<InputBridge>.fromOpaque(userInfo).takeUnretainedValue()
            return bridge.handle(type: type, event: event)
        }, userInfo: userInfo) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func uninstall() {
        releaseCapture()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        wallpaperClicks = WallpaperClickGuard()
    }

    func update(geometry: StageGeometry?, virtualBounds: CGRect?, physicalBounds: [CGRect], interactive: Bool) {
        let geometryChanged = fence.geometry != geometry || fence.virtualBounds != virtualBounds
        // Release using the old mapping when a display or the stage moves underneath the cursor.
        fence.physicalBounds = physicalBounds
        if fence.isCaptured, geometryChanged || !interactive { releaseCapture() }
        fence.geometry = geometry
        fence.virtualBounds = virtualBounds
        fence.physicalBounds = physicalBounds
        fence.interactive = interactive
        if fence.isCaptured, geometry == nil || !interactive { releaseCapture() }
    }

    /// Puts the pointer back on the physical screen if it is currently on the virtual display.
    func releaseCapture() {
        guard let decision = fence.release() else { return }
        apply(decision, to: nil)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            guard let hotkey = Hotkey.match(keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags) else {
                return Unmanaged.passUnretained(event)
            }
            // AX calls can take seconds across several windows. Never run those inside the tap callback.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.onHotkey?(hotkey) }
                }
            }
            return nil
        default:
            let isMovement = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type)
            let delta = isMovement ? CGVector(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY)) : .zero
            let decision = fence.process(location: event.location, rawDelta: delta) { point in self.stageIsTopmost(at: point) }
            let target = decision.location ?? event.location
            let consumed = wallpaperClicks.consumes(type, captured: fence.isCaptured, flags: event.flags) {
                // Use the mapped virtual point, not the physical stage window under the user's hand.
                self.targetIsWallpaper(at: target)
            }
            apply(decision, to: event, delivered: !consumed)
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
    }

    private func apply(_ decision: CursorFence.Decision, to event: CGEvent?, delivered: Bool = true) {
        if let location = decision.location { event?.location = location }
        // Rewriting a HID-level event's location already moves the cursor there, and every warp makes macOS suppress
        // hardware pointer events for a moment, which shows as stutter. So the cursor is only warped for the jumps between
        // displays: capture, release, and keeping a free pointer off the virtual display.
        // A consumed event cannot move the system cursor itself; keep tracking even during a swallowed drag.
        let tracking = delivered && event != nil && fence.isCaptured && decision.transition == nil
        if let warp = decision.warp, !tracking {
            _ = CGWarpMouseCursorPosition(warp)
            // Re-associating the cursor lifts the post-warp suspension immediately.
            _ = CGAssociateMouseAndMouseCursorPosition(1)
        }
        if let transition = decision.transition {
            MainActor.assumeIsolated { onTransition?(transition) }
        }
    }

    /// Whether the stage window is the window under `point` (global coordinates) — nothing else is covering it there.
    private func stageIsTopmost(at point: CGPoint) -> Bool {
        let windowNumber = stageWindowNumber
        guard windowNumber != 0 else { return false }
        return self.windowNumber(at: point) == windowNumber
    }

    private func targetIsWallpaper(at point: CGPoint) -> Bool {
        let number = windowNumber(at: point)
        var layer: CGWindowLevel?
        if let number, number > 0, let identifier = CGWindowID(exactly: number) {
            // Query only the hit window, and only on primary down, to keep movement events out of window enumeration.
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, identifier) as? [[String: Any]]
            layer = (info?.first?[kCGWindowLayer as String] as? NSNumber)?.int32Value
        }
        return WallpaperClickGuard.isWallpaper(windowNumber: number, windowLayer: layer)
    }

    private func windowNumber(at point: CGPoint) -> Int? {
        return MainActor.assumeIsolated {
            guard let primary = NSScreen.screens.first else { return nil }
            let appKitPoint = NSPoint(x: point.x, y: primary.frame.height - point.y)
            return NSWindow.windowNumber(at: appKitPoint, belowWindowWithWindowNumber: 0)
        }
    }
}
