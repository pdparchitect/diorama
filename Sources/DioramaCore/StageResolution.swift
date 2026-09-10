import Foundation

/// A Retina (2×) resolution offered for the virtual display. `pixelWidth` is the backing size; the desktop "looks like" half of it.
public struct StageResolution: Sendable, Hashable, Identifiable, Codable {
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(pixelWidth: Int, pixelHeight: Int) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var id: String { "\(pixelWidth)x\(pixelHeight)" }
    public var pointWidth: Int { pixelWidth / 2 }
    public var pointHeight: Int { pixelHeight / 2 }
    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    public var pointSize: CGSize { CGSize(width: pointWidth, height: pointHeight) }
    public var label: String { "\(pointWidth) × \(pointHeight) (\(pixelWidth) × \(pixelHeight) pixels)" }

    public static let all: [StageResolution] = [
        StageResolution(pixelWidth: 3840, pixelHeight: 2160),
        StageResolution(pixelWidth: 3456, pixelHeight: 2160),
        StageResolution(pixelWidth: 3200, pixelHeight: 1800),
        StageResolution(pixelWidth: 2880, pixelHeight: 1800),
        StageResolution(pixelWidth: 2560, pixelHeight: 1600),
        StageResolution(pixelWidth: 2560, pixelHeight: 1440),
        StageResolution(pixelWidth: 2048, pixelHeight: 1152)
    ]

    public static let `default` = StageResolution(pixelWidth: 3840, pixelHeight: 2160)

    /// The largest backing size any offered resolution needs.
    public static var maximumPixelSize: CGSize {
        CGSize(width: all.map(\.pixelWidth).max() ?? 0, height: all.map(\.pixelHeight).max() ?? 0)
    }

    public static func named(_ id: String) -> StageResolution? { all.first { $0.id == id } }
}
