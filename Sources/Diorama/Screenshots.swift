import AppKit
import DioramaCore
// macOS 15 SDK headers predate ScreenCaptureKit's Sendable annotations. Content snapshots are read on MainActor.
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

/// Full-resolution stills of the virtual display: the complete desktop, wallpaper and menu bar included, without the cursor.
@MainActor
enum Screenshots {
    static var directory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("Diorama", isDirectory: true)
    }

    static func capture(displayID: CGDirectDisplayID, pixelSize: CGSize) async throws -> CGImage {
        let content = try await ShareableContent.current()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw DioramaError.displayNotShareable }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw DioramaError.message("Cannot encode PNG.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw DioramaError.message("Cannot encode PNG.") }
        return data as Data
    }

    @discardableResult
    static func save(_ image: CGImage, date: Date = Date(), directory: URL = Screenshots.directory) throws -> URL {
        let data = try pngData(image)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appendingPathComponent(ScreenshotNaming.filename(date: date))
        var suffix = 1
        while true {
            let url = suffix == 1 ? base : base.deletingPathExtension().appendingPathExtension("\(suffix).png")
            do {
                // Exclusive creation also protects against another Diorama process saving in the same second.
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                suffix += 1
            }
        }
    }

    static func copy(_ image: CGImage) throws {
        let data = try pngData(image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { throw DioramaError.message("Cannot write to the clipboard.") }
    }

    static func openInPreview(_ url: URL) async throws {
        let workspace = NSWorkspace.shared
        guard let preview = workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            throw DioramaError.message("Preview could not be found.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await workspace.open([url], withApplicationAt: preview, configuration: configuration)
    }
}
