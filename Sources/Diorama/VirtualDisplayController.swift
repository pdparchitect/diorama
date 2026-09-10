import AppKit
import CGVirtualDisplayShim
import DioramaCore

enum DioramaError: LocalizedError {
    case displayCreation
    case displayNotShareable
    case screenRecordingDenied
    case noFrontWindow
    case message(String)

    var errorDescription: String? {
        switch self {
        case .displayCreation: "macOS refused to create the virtual display."
        case .displayNotShareable: "The virtual display is not available for capture yet."
        case .screenRecordingDenied: "Screen Recording access is required to show the virtual display."
        case .noFrontWindow: "Activate another application's window first."
        case .message(let text): text
        }
    }
}

/// Owns the virtual display. The display exists for as long as this object holds the `CGVirtualDisplay` instance; macOS
/// removes it when the object is released or the process exits, and moves any windows on it back to a remaining display.
@MainActor
final class VirtualDisplayController {
    private static let vendorID: UInt32 = 0x4F52
    private static let productID: UInt32 = 0xD10A
    private static let serialNumber: UInt32 = 1

    private var display: CGVirtualDisplay?
    private(set) var displayID: CGDirectDisplayID = 0

    var exists: Bool { display != nil }

    /// Bounds in global coordinates, or `.zero` until macOS has brought the display online.
    var bounds: CGRect {
        guard displayID != 0 else { return .zero }
        let bounds = CGDisplayBounds(displayID)
        return CGDisplayIsActive(displayID) != 0 ? bounds : .zero
    }

    var pixelSize: CGSize {
        guard displayID != 0 else { return .zero }
        return CGSize(width: CGDisplayPixelsWide(displayID), height: CGDisplayPixelsHigh(displayID))
    }

    func create() throws {
        guard display == nil else { return }
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = "Diorama"
        let maximum = StageResolution.maximumPixelSize
        descriptor.maxPixelsWide = UInt32(maximum.width)
        descriptor.maxPixelsHigh = UInt32(maximum.height)
        // A 16:9 panel of roughly 27 inches, so macOS treats the modes as Retina at the sizes offered.
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 338)
        descriptor.vendorID = Self.vendorID
        descriptor.productID = Self.productID
        descriptor.serialNum = Self.serialNumber
        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = StageResolution.all.map { CGVirtualDisplayMode(width: UInt32($0.pixelWidth), height: UInt32($0.pixelHeight), refreshRate: 60) }
        guard display.applySettings(settings) else { throw DioramaError.displayCreation }
        self.display = display
        displayID = display.displayID
    }

    func destroy() {
        display = nil
        displayID = 0
    }

    /// The resolution the display is currently showing, if it matches one that is offered.
    var currentResolution: StageResolution? {
        let size = pixelSize
        return StageResolution.all.first { $0.pixelSize == size }
    }

    /// Switches the display to a Retina mode with the given backing size. Returns false when no such mode is available.
    @discardableResult
    func apply(_ resolution: StageResolution) -> Bool {
        guard displayID != 0, let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else { return false }
        guard let mode = modes.first(where: {
            $0.pixelWidth == resolution.pixelWidth && $0.pixelHeight == resolution.pixelHeight && $0.width == resolution.pointWidth
        }) else { return false }
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else { return false }
        CGConfigureDisplayWithDisplayMode(configuration, displayID, mode, nil)
        return CGCompleteDisplayConfiguration(configuration, .permanently) == .success
    }

    /// Bounds of every other active display, in global coordinates.
    func otherDisplayBounds() -> [CGRect] {
        var identifiers = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(identifiers.count), &identifiers, &count) == .success else { return [] }
        return identifiers.prefix(Int(count)).filter { $0 != displayID }.map { CGDisplayBounds($0) }
    }
}
