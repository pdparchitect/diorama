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
    }

    func update(geometry: StageGeometry?, virtualBounds: CGRect?, physicalBounds: [CGRect], interactive: Bool) {
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
            MainActor.assumeIsolated { onHotkey?(hotkey) }
            return nil
        default:
            let delta = CGVector(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
            let decision = fence.process(location: event.location, rawDelta: delta) { point in self.stageIsTopmost(at: point) }
            apply(decision, to: event)
            return Unmanaged.passUnretained(event)
        }
    }

    private func apply(_ decision: CursorFence.Decision, to event: CGEvent?) {
        if let location = decision.location { event?.location = location }
        if let warp = decision.warp {
            _ = CGWarpMouseCursorPosition(warp)
            // Warping suspends hardware pointer events for a moment; re-associating the cursor lifts that suspension immediately.
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
        return MainActor.assumeIsolated {
            guard let primary = NSScreen.screens.first else { return false }
            let appKitPoint = NSPoint(x: point.x, y: primary.frame.height - point.y)
            return NSWindow.windowNumber(at: appKitPoint, belowWindowWithWindowNumber: 0) == windowNumber
        }
    }
}
