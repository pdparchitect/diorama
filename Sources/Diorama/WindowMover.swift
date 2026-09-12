import AppKit
import ApplicationServices

/// Moves other applications' windows between displays through the Accessibility API.
/// Positions are in global coordinates (top-left origin), the same space the virtual display bounds use.
@MainActor
enum WindowMover {
    private static let timeout: Float = 0.5

    struct Placement {
        var window: AXUIElement
        var frame: CGRect
    }

    /// The focused window of the frontmost application, unless that application is Diorama itself.
    static func frontWindow(of application: NSRunningApplication) -> Placement? {
        guard !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let window = copyElement(element, attribute: kAXFocusedWindowAttribute), let frame = frame(of: window) else { return nil }
        return Placement(window: window, frame: frame)
    }

    /// Every window of every regular application whose top-left corner lies inside `bounds`.
    static func windows(inside bounds: CGRect) -> [Placement] {
        var result: [Placement] = []
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular && application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let element = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(element, timeout)
            for window in copyElements(element, attribute: kAXWindowsAttribute) {
                if let frame = frame(of: window), bounds.contains(frame.origin) { result.append(Placement(window: window, frame: frame)) }
            }
        }
        return result
    }

    /// Moves a window onto `display`, keeping its size where it fits and centring it otherwise.
    @discardableResult
    static func move(_ placement: Placement, to display: CGRect) -> Bool {
        var size = placement.frame.size
        if size.width > display.width || size.height > display.height {
            size = CGSize(width: min(size.width, display.width), height: min(size.height, display.height))
            setSize(size, of: placement.window)
        }
        let origin = CGPoint(x: display.minX + max(0, (display.width - size.width) / 2).rounded(), y: display.minY + max(0, (display.height - size.height) / 2).rounded())
        return setPosition(origin, of: placement.window)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copyValue(window, attribute: kAXPositionAttribute), let sizeValue = copyValue(window, attribute: kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func setPosition(_ position: CGPoint, of window: AXUIElement) -> Bool {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private static func copyAttribute(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute: attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
        guard let array = copyAttribute(element, attribute: attribute) as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeDowncast(item, to: AXUIElement.self) : nil
        }
    }

    private static func copyValue(_ element: AXUIElement, attribute: String) -> AXValue? {
        guard let value = copyAttribute(element, attribute: attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
