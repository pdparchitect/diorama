import Foundation

public enum ScreenshotNaming {
    /// A file name in the style of macOS screenshots, e.g. `Diorama 2026-09-10 at 21.30.15.png`.
    public static func filename(date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Diorama \(formatter.string(from: date)).png"
    }
}
