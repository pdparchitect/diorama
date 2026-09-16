import CoreGraphics

/// Keeps a wallpaper click in the stage from invoking the session-wide Show Desktop gesture.
/// A swallowed down owns the rest of that primary-button gesture, even after the pointer leaves the stage.
public struct WallpaperClickGuard: Sendable {
    private var suppressingPrimaryGesture = false

    public init() {}

    /// AppKit can hit Finder's desktop window rather than report empty wallpaper. Its desktop layer distinguishes it
    /// from ordinary Finder windows; widgets, the Dock, menus, and application windows sit above the desktop layers.
    public static func isWallpaper(windowNumber: Int?, windowLayer: CGWindowLevel?) -> Bool {
        guard let windowNumber else { return false }
        if windowNumber == 0 { return true }
        guard let windowLayer else { return false }
        return windowLayer <= CGWindowLevelForKey(.desktopIconWindow)
    }

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
