import Foundation

/// Decides, for every pointer event, where the cursor is allowed to be.
///
/// The fence has two jobs. While the pointer is **free** it keeps the cursor off the virtual display, so the pointer can never
/// wander onto a screen nobody can see. While the pointer is **captured** it lives on the virtual display, and the fence keeps
/// a *shadow* — the position the person believes the pointer has on their physical screen, inside the stage. Every movement
/// updates the shadow and the cursor is placed at the matching point on the virtual display, so the picture in the stage
/// follows the hand exactly. Leaving the stage, or pushing against the edge of the virtual display, releases the pointer and
/// puts it back on the physical screen where the shadow is.
///
/// The fence is pure state: the caller feeds it event locations and applies the returned decision (rewrite the event location,
/// warp the cursor, react to a transition). This keeps the policy testable without a window server.
public struct CursorFence: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case free
        /// `shadow` is in stage (physical screen) coordinates, `target` is where the cursor was last placed on the display.
        case captured(shadow: CGPoint, target: CGPoint)
    }

    public enum Transition: Sendable, Equatable {
        case entered
        case exited
    }

    public struct Decision: Sendable, Equatable {
        /// New location for the event, or `nil` to leave the event untouched.
        public var location: CGPoint?
        /// Where the cursor should be warped, or `nil` for no warp.
        public var warp: CGPoint?
        public var transition: Transition?

        public init(location: CGPoint? = nil, warp: CGPoint? = nil, transition: Transition? = nil) {
            self.location = location
            self.warp = warp
            self.transition = transition
        }

        public static let passthrough = Decision()
    }

    public private(set) var mode: Mode = .free
    /// When false the stage is view-only: the pointer is never captured, but the virtual display stays fenced off.
    public var interactive = true
    /// Stage and display rectangles; `nil` while the stage is not visible or no display exists.
    public var geometry: StageGeometry?
    /// Bounds of the virtual display; `nil` while no display exists.
    public var virtualBounds: CGRect?
    /// Bounds of every display the cursor may rest on.
    public var physicalBounds: [CGRect] = []
    /// Set after a release; the pointer must be seen outside the stage before it can be captured again, so a release at the
    /// stage edge does not immediately re-capture.
    public private(set) var armed = true

    private struct ReleaseHandoff: Sendable, Equatable {
        var point: CGPoint
        let display: CGRect
    }
    /// Events already queued at release may still use virtual coordinates until the warp reaches WindowServer.
    private var releaseHandoff: ReleaseHandoff?

    public init() {}

    public var isCaptured: Bool {
        if case .captured = mode { return true }
        return false
    }

    /// Processes one pointer event.
    /// - Parameters:
    ///   - location: the event location in global coordinates.
    ///   - rawDelta: relative movement reported by a move/drag event, or zero for clicks and scrolling. Used when display
    ///     boundaries or a pending release warp make absolute coordinates unreliable.
    ///   - stageHit: whether the stage window is the topmost window at a point on the physical screen.
    public mutating func process(location: CGPoint, rawDelta: CGVector, stageHit: (CGPoint) -> Bool) -> Decision {
        switch mode {
        case .free:
            return processFree(location: location, rawDelta: rawDelta, stageHit: stageHit)
        case .captured(let shadow, let target):
            return processCaptured(location: location, rawDelta: rawDelta, shadow: shadow, target: target, stageHit: stageHit)
        }
    }

    /// Forces the pointer back onto the physical screen, for example when interaction is switched off or the stage window closes.
    public mutating func release() -> Decision? {
        guard case .captured(let shadow, _) = mode else { return nil }
        return finishRelease(at: shadow)
    }

    private mutating func finishRelease(at shadow: CGPoint) -> Decision {
        mode = .free
        armed = false
        let point = Clamp.point(shadow, intoAnyOf: physicalBounds)
        releaseHandoff = (geometry?.display ?? virtualBounds).map { ReleaseHandoff(point: point, display: $0) }
        return Decision(location: point, warp: point, transition: .exited)
    }

    private mutating func processFree(location: CGPoint, rawDelta: CGVector, stageHit: (CGPoint) -> Bool) -> Decision {
        if var handoff = releaseHandoff, handoff.display.contains(location) {
            // Continue from the window's exit point, not the physical screen nearest the stale virtual location.
            handoff.point = Clamp.point(CGPoint(x: handoff.point.x + rawDelta.dx, y: handoff.point.y + rawDelta.dy), intoAnyOf: physicalBounds)
            releaseHandoff = handoff
            if geometry?.stage.contains(handoff.point) != true { armed = true }
            return Decision(location: handoff.point, warp: handoff.point)
        }
        releaseHandoff = nil
        if let virtualBounds, virtualBounds.contains(location), !physicalBounds.isEmpty {
            let clamped = Clamp.point(location, intoAnyOf: physicalBounds)
            return Decision(location: clamped, warp: clamped)
        }
        guard let geometry, geometry.stage.contains(location) else {
            armed = true
            return .passthrough
        }
        guard interactive, armed, stageHit(location) else { return .passthrough }
        let target = geometry.toDisplay(location)
        mode = .captured(shadow: location, target: target)
        return Decision(location: target, warp: target, transition: .entered)
    }

    private mutating func processCaptured(location: CGPoint, rawDelta: CGVector, shadow: CGPoint, target: CGPoint, stageHit: (CGPoint) -> Bool) -> Decision {
        var movement = CGVector(dx: location.x - target.x, dy: location.y - target.y)
        var push = CGVector.zero
        if let geometry {
            let display = geometry.display
            // At a display boundary, macOS can clip or relocate the absolute position. Relative motion retains both
            // axes of a diagonal move and its overshoot instead of mistaking a display jump for hand movement.
            if location.x <= display.minX || location.x >= display.maxX - 1 ||
                location.y <= display.minY || location.y >= display.maxY - 1 {
                movement = rawDelta
            }
            if location.x <= display.minX, rawDelta.dx < 0 { push.dx = -1 }
            if location.x >= display.maxX - 1, rawDelta.dx > 0 { push.dx = 1 }
            if location.y <= display.minY, rawDelta.dy < 0 { push.dy = -1 }
            if location.y >= display.maxY - 1, rawDelta.dy > 0 { push.dy = 1 }
        }
        var shadow = CGPoint(x: shadow.x + movement.dx, y: shadow.y + movement.dy)
        let pushing = push != .zero
        if interactive, !pushing, let geometry, geometry.stage.contains(shadow), stageHit(shadow) {
            let newTarget = geometry.toDisplay(shadow)
            mode = .captured(shadow: shadow, target: newTarget)
            return Decision(location: newTarget, warp: newTarget)
        }
        if pushing, let geometry {
            // Step outside if still pinned inside the picture, preserving any movement already beyond its edge.
            if push.dx < 0 { shadow.x = min(shadow.x, geometry.stage.minX - 1) }
            if push.dx > 0 { shadow.x = max(shadow.x, geometry.stage.maxX + 1) }
            if push.dy < 0 { shadow.y = min(shadow.y, geometry.stage.minY - 1) }
            if push.dy > 0 { shadow.y = max(shadow.y, geometry.stage.maxY + 1) }
        }
        return finishRelease(at: shadow)
    }
}
