import CoreGraphics

/// Global keyboard shortcuts. All use Control-Option-Command so they never collide with an application's own shortcuts.
public enum Hotkey: CaseIterable, Sendable, Equatable {
    case sendFrontWindow
    case returnFrontWindow
    case returnAllWindows
    case saveScreenshot
    case toggleInteractive

    /// Virtual key code of the letter, as reported by `CGEvent`.
    public var keyCode: Int64 {
        switch self {
        case .sendFrontWindow: 2 // D
        case .returnFrontWindow: 11 // B
        case .returnAllWindows: 15 // R
        case .saveScreenshot: 1 // S
        case .toggleInteractive: 34 // I
        }
    }

    public var letter: String {
        switch self {
        case .sendFrontWindow: "D"
        case .returnFrontWindow: "B"
        case .returnAllWindows: "R"
        case .saveScreenshot: "S"
        case .toggleInteractive: "I"
        }
    }

    public var title: String {
        switch self {
        case .sendFrontWindow: "Send Front Window to Diorama"
        case .returnFrontWindow: "Return Front Window"
        case .returnAllWindows: "Return All Windows"
        case .saveScreenshot: "Save Screenshot"
        case .toggleInteractive: "Interactive"
        }
    }

    public static let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    private static let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    /// The hotkey for a key-down event, if its key code and modifiers match exactly (Shift or a missing modifier disqualifies it).
    public static func match(keyCode: Int64, flags: CGEventFlags) -> Hotkey? {
        guard flags.intersection(relevant) == modifiers else { return nil }
        return allCases.first { $0.keyCode == keyCode }
    }
}
