import CoreGraphics

/// Keeps a wallpaper click in the stage from invoking the session-wide Show Desktop gesture.
/// A swallowed down owns the rest of that primary-button gesture, even after the pointer leaves the stage.
public struct WallpaperClickGuard: Sendable {
    private var suppressingPrimaryGesture = false

    public init() {}

    public mutating func consumes(_ type: CGEventType, captured: Bool, flags: CGEventFlags = [], targetIsWallpaper: () -> Bool) -> Bool {
        switch type {
        case .leftMouseDown:
            suppressingPrimaryGesture = captured && !flags.contains(.maskControl) && targetIsWallpaper()
            return suppressingPrimaryGesture
        case .leftMouseDragged:
            return suppressingPrimaryGesture
        case .leftMouseUp:
            let consumed = suppressingPrimaryGesture
            suppressingPrimaryGesture = false
            return consumed
        default:
            return false
        }
    }
}
