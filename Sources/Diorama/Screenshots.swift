import AppKit
import DioramaCore
import ScreenCaptureKit
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
    static func save(_ image: CGImage, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(ScreenshotNaming.filename(date: date))
        try pngData(image).write(to: url, options: .atomic)
        return url
    }

    static func copy(_ image: CGImage) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(try pngData(image), forType: .png)
    }
}
