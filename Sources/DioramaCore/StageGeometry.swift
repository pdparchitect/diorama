import Foundation

/// Maps between the stage (where the virtual display is drawn on a physical screen) and the virtual display itself.
///
/// Both rectangles use global Core Graphics coordinates: the origin is the top-left corner of the primary display and
/// `y` grows downward, which is the coordinate space used by `CGEvent`, `CGDisplayBounds` and the Accessibility API.
public struct StageGeometry: Sendable, Equatable {
    public var stage: CGRect
    public var display: CGRect

    public init(stage: CGRect, display: CGRect) {
        self.stage = stage
        self.display = display
    }

    /// Display points per stage point.
    public var scale: CGFloat { stage.width > 0 ? display.width / stage.width : 1 }

    public func toDisplay(_ point: CGPoint) -> CGPoint {
        CGPoint(x: display.minX + (point.x - stage.minX) * scale, y: display.minY + (point.y - stage.minY) * scale)
    }

    public func toStage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: stage.minX + (point.x - display.minX) / scale, y: stage.minY + (point.y - display.minY) / scale)
    }

    /// The largest rectangle with the aspect ratio of `size` that fits centred inside `container`.
    public static func fit(_ size: CGSize, in container: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / size.width, container.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: container.midX - fitted.width / 2, y: container.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}

public enum Clamp {
    /// The nearest point inside `rect`. Display bounds are half-open, so the far edges are excluded to keep the result a valid cursor position.
    public static func point(_ point: CGPoint, into rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX - 1), y: min(max(point.y, rect.minY), rect.maxY - 1))
    }

    /// The nearest point inside any of `rects`; `point` itself when `rects` is empty.
    public static func point(_ point: CGPoint, intoAnyOf rects: [CGRect]) -> CGPoint {
        var best = point
        var bestDistance = CGFloat.infinity
        for rect in rects where rect.width > 0 && rect.height > 0 {
            let candidate = Clamp.point(point, into: rect)
            let distance = hypot(candidate.x - point.x, candidate.y - point.y)
            if distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }
}
