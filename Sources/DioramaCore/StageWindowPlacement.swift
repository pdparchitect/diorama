import Foundation

/// Keeps the viewer off the display it is showing. All rectangles must use the same coordinate space.
public enum StageWindowPlacement {
    public static func constrain(_ frame: CGRect, virtualBounds: CGRect, physicalBounds: [CGRect]) -> CGRect {
        let screens = physicalBounds.filter { !$0.isEmpty }
        guard !frame.isEmpty, !virtualBounds.isEmpty, !screens.isEmpty else { return frame }
        // Preserve ordinary positioning, including windows spanning multiple physical monitors.
        guard frame.intersects(virtualBounds) || !screens.contains(where: { frame.intersects($0) }) else { return frame }

        // Prefer the screen that already holds most of the window; use distance when it is entirely off-screen.
        let screen = screens.max { lhs, rhs in
            let left = frame.intersection(lhs)
            let right = frame.intersection(rhs)
            let leftArea = left.isNull ? 0 : left.width * left.height
            let rightArea = right.isNull ? 0 : right.width * right.height
            if leftArea != rightArea { return leftArea < rightArea }
            return distance(from: frame, to: lhs) > distance(from: frame, to: rhs)
        }!
        let size = CGSize(width: min(frame.width, screen.width), height: min(frame.height, screen.height))
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }

    private static func distance(from frame: CGRect, to screen: CGRect) -> CGFloat {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let nearest = Clamp.point(center, into: screen)
        return hypot(center.x - nearest.x, center.y - nearest.y)
    }
}
