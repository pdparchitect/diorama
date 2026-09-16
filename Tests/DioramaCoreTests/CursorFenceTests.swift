import XCTest
@testable import DioramaCore

final class CursorFenceTests: XCTestCase {
    let physical = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let virtual = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
    let stage = CGRect(x: 200, y: 300, width: 960, height: 540)

    func makeFence(interactive: Bool = true) -> CursorFence {
        var fence = CursorFence()
        fence.interactive = interactive
        fence.geometry = StageGeometry(stage: stage, display: virtual)
        fence.virtualBounds = virtual
        fence.physicalBounds = [physical]
        return fence
    }

    func move(_ fence: inout CursorFence, to point: CGPoint, delta: CGVector = .zero, hit: Bool = true) -> CursorFence.Decision {
        fence.process(location: point, rawDelta: delta) { _ in hit }
    }

    func testFreePointerOutsideStageIsUntouched() {
        var fence = makeFence()
        XCTAssertEqual(move(&fence, to: CGPoint(x: 50, y: 50)), .passthrough)
        XCTAssertFalse(fence.isCaptured)
    }

    func testFreePointerIsKeptOffTheVirtualDisplay() {
        var fence = makeFence()
        let decision = move(&fence, to: CGPoint(x: 1740, y: 500))
        XCTAssertEqual(decision.location, CGPoint(x: 1727, y: 500))
        XCTAssertEqual(decision.warp, CGPoint(x: 1727, y: 500))
        XCTAssertNil(decision.transition)
        XCTAssertFalse(fence.isCaptured)
    }

    func testEnteringTheStageCapturesAndMapsToDisplay() {
        var fence = makeFence()
        let decision = move(&fence, to: CGPoint(x: 680, y: 570))
        XCTAssertEqual(decision.transition, .entered)
        XCTAssertEqual(decision.location, CGPoint(x: 2688, y: 540))
        XCTAssertEqual(decision.warp, CGPoint(x: 2688, y: 540))
        XCTAssertEqual(fence.mode, .captured(shadow: CGPoint(x: 680, y: 570), target: CGPoint(x: 2688, y: 540)))
    }

    func testStageCoveredByAnotherWindowDoesNotCapture() {
        var fence = makeFence()
        XCTAssertEqual(move(&fence, to: CGPoint(x: 680, y: 570), hit: false), .passthrough)
        XCTAssertFalse(fence.isCaptured)
    }

    func testViewOnlyStageNeverCapturesButStillFences() {
        var fence = makeFence(interactive: false)
        XCTAssertEqual(move(&fence, to: CGPoint(x: 680, y: 570)), .passthrough)
        XCTAssertEqual(move(&fence, to: CGPoint(x: 1800, y: 10)).warp, CGPoint(x: 1727, y: 10))
    }

    func testCapturedMovementFollowsTheHandOneToOne() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 680, y: 570))
        // The hardware moved the cursor 10 points right and 4 down from where it was placed on the display.
        let decision = move(&fence, to: CGPoint(x: 2698, y: 544), delta: CGVector(dx: 10, dy: 4))
        XCTAssertNil(decision.transition)
        XCTAssertEqual(decision.location, CGPoint(x: 2708, y: 548))
        XCTAssertEqual(decision.warp, CGPoint(x: 2708, y: 548))
        XCTAssertEqual(fence.mode, .captured(shadow: CGPoint(x: 690, y: 574), target: CGPoint(x: 2708, y: 548)))
    }

    func testClicksWithoutMovementStayOnTarget() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 680, y: 570))
        let decision = move(&fence, to: CGPoint(x: 2688, y: 540))
        XCTAssertEqual(decision.location, CGPoint(x: 2688, y: 540))
        XCTAssertNil(decision.transition)
    }

    func testLeavingTheStageReleasesAtTheShadow() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 210, y: 570)) // placed at x = 1748 on the display
        // Moving 15 points left takes the shadow past the stage's left edge (x = 200) without reaching the display's edge.
        let decision = move(&fence, to: CGPoint(x: 1733, y: 540), delta: CGVector(dx: -15, dy: 0))
        XCTAssertEqual(decision.transition, .exited)
        XCTAssertEqual(decision.warp, CGPoint(x: 195, y: 570))
        XCTAssertEqual(decision.location, CGPoint(x: 195, y: 570))
        XCTAssertFalse(fence.isCaptured)
        XCTAssertFalse(fence.armed)
    }

    func testPushingAgainstTheDisplayEdgeReleasesBesideThePicture() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 1150, y: 570)) // near the stage's right edge (x = 1160)
        // The cursor is pinned at the display's far right edge and the hand keeps pushing right.
        let pinned = CGPoint(x: virtual.maxX - 1, y: 540)
        let decision = move(&fence, to: pinned, delta: CGVector(dx: 6, dy: 0))
        XCTAssertEqual(decision.transition, .exited)
        XCTAssertEqual(decision.warp, CGPoint(x: 1161, y: 570))
        XCTAssertFalse(fence.isCaptured)
    }

    func testCornerExitsPreserveBothAxesAndOvershoot() {
        for dx: CGFloat in [-30, 30] {
            for dy: CGFloat in [-25, 25] {
                var fence = makeFence()
                let start = CGPoint(x: dx < 0 ? stage.minX + 10 : stage.maxX - 10,
                                    y: dy < 0 ? stage.minY + 10 : stage.maxY - 10)
                _ = move(&fence, to: start)
                let pinned = CGPoint(x: dx < 0 ? virtual.minX : virtual.maxX - 1,
                                     y: dy < 0 ? virtual.minY : virtual.maxY - 1)
                let decision = move(&fence, to: pinned, delta: CGVector(dx: dx, dy: dy))
                let expected = CGPoint(x: start.x + dx, y: start.y + dy)
                XCTAssertEqual(decision.transition, .exited)
                XCTAssertEqual(decision.location, expected)
                XCTAssertEqual(decision.warp, expected)
            }
        }
    }

    func testDisplayBoundaryDoesNotTurnRelocationIntoHandMovement() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 210, y: 310))
        // The location is on a different display, but the hand only moved a few points diagonally.
        let decision = move(&fence, to: .zero, delta: CGVector(dx: -15, dy: -20))
        XCTAssertEqual(decision.transition, .exited)
        XCTAssertEqual(decision.location, CGPoint(x: 195, y: 290))
        XCTAssertEqual(decision.warp, CGPoint(x: 195, y: 290))
    }

    func testQueuedVirtualEventsAfterExitContinueFromTheWindow() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 210, y: 570))
        _ = move(&fence, to: CGPoint(x: 1733, y: 540), delta: CGVector(dx: -15, dy: 0))

        // These events were positioned before the release warp took effect.
        let first = move(&fence, to: CGPoint(x: 1730, y: 542), delta: CGVector(dx: -3, dy: 2))
        XCTAssertEqual(first.location, CGPoint(x: 192, y: 572))
        XCTAssertEqual(first.warp, CGPoint(x: 192, y: 572))
        XCTAssertNil(first.transition)
        let second = move(&fence, to: CGPoint(x: 1728, y: 544), delta: CGVector(dx: -2, dy: 2))
        XCTAssertEqual(second.location, CGPoint(x: 190, y: 574))
        XCTAssertFalse(fence.isCaptured)

        // Once events report physical coordinates again, normal movement and fencing resume.
        XCTAssertEqual(move(&fence, to: CGPoint(x: 188, y: 576), delta: CGVector(dx: -2, dy: 2)), .passthrough)
        XCTAssertEqual(move(&fence, to: CGPoint(x: 1740, y: 500)).warp, CGPoint(x: 1727, y: 500))
    }

    func testQueuedClickAfterExplicitReleaseStaysAtTheReleasePoint() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 680, y: 570))
        _ = fence.release()
        let decision = move(&fence, to: CGPoint(x: 2688, y: 540))
        XCTAssertEqual(decision.location, CGPoint(x: 680, y: 570))
        XCTAssertEqual(decision.warp, CGPoint(x: 680, y: 570))
        XCTAssertNil(decision.transition)
        XCTAssertFalse(fence.isCaptured)
        XCTAssertFalse(fence.armed)
    }

    func testReleaseHandoffWorksWithVirtualDisplayOnEitherSideOrAboveOrBelow() {
        for origin in [CGPoint(x: -1920, y: 0), CGPoint(x: 1728, y: 0),
                       CGPoint(x: 0, y: -1080), CGPoint(x: 0, y: 1117)] {
            var fence = makeFence()
            let display = CGRect(origin: origin, size: virtual.size)
            let geometry = StageGeometry(stage: stage, display: display)
            fence.geometry = geometry
            fence.virtualBounds = display
            _ = move(&fence, to: CGPoint(x: 210, y: 570))
            let target = geometry.toDisplay(CGPoint(x: 210, y: 570))
            let exit = move(&fence, to: CGPoint(x: target.x - 15, y: target.y), delta: CGVector(dx: -15, dy: 0))
            XCTAssertEqual(exit.location, CGPoint(x: 195, y: 570))
            let queued = move(&fence, to: CGPoint(x: target.x - 18, y: target.y), delta: CGVector(dx: -3, dy: 0))
            XCTAssertEqual(queued.location, CGPoint(x: 192, y: 570))
            XCTAssertNil(queued.transition)
        }
    }

    func testReleaseRequiresLeavingTheStageBeforeRecapturing() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 210, y: 570))
        _ = move(&fence, to: CGPoint(x: 1728, y: 540), delta: CGVector(dx: -20, dy: 0))
        XCTAssertFalse(fence.armed)
        XCTAssertEqual(move(&fence, to: CGPoint(x: 205, y: 570)), .passthrough)
        XCTAssertFalse(fence.isCaptured)
        XCTAssertEqual(move(&fence, to: CGPoint(x: 150, y: 570)), .passthrough)
        XCTAssertTrue(fence.armed)
        XCTAssertEqual(move(&fence, to: CGPoint(x: 205, y: 570)).transition, .entered)
    }

    func testStageDisappearingWhileCapturedReleases() {
        var fence = makeFence()
        _ = move(&fence, to: CGPoint(x: 680, y: 570))
        fence.geometry = nil
        let decision = move(&fence, to: CGPoint(x: 2688, y: 540))
        XCTAssertEqual(decision.transition, .exited)
        XCTAssertEqual(decision.warp, CGPoint(x: 680, y: 570))
    }

    func testExplicitReleaseWarpsBackToTheShadow() {
        var fence = makeFence()
        XCTAssertNil(fence.release())
        _ = move(&fence, to: CGPoint(x: 680, y: 570))
        let decision = fence.release()
        XCTAssertEqual(decision?.transition, .exited)
        XCTAssertEqual(decision?.warp, CGPoint(x: 680, y: 570))
        XCTAssertFalse(fence.isCaptured)
    }

    func testHotkeysRequireExactModifiers() {
        XCTAssertEqual(Hotkey.match(keyCode: 2, flags: [.maskControl, .maskAlternate, .maskCommand]), .sendFrontWindow)
        XCTAssertEqual(Hotkey.match(keyCode: 1, flags: [.maskControl, .maskAlternate, .maskCommand, .maskNonCoalesced]), .saveScreenshot)
        XCTAssertNil(Hotkey.match(keyCode: 2, flags: [.maskCommand]))
        XCTAssertNil(Hotkey.match(keyCode: 2, flags: [.maskControl, .maskAlternate, .maskCommand, .maskShift]))
        XCTAssertNil(Hotkey.match(keyCode: 99, flags: [.maskControl, .maskAlternate, .maskCommand]))
    }

    func testScreenshotNaming() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        XCTAssertEqual(ScreenshotNaming.filename(date: date, calendar: calendar), "Diorama 2026-09-10 at 00.26.40.png")
    }

    func testResolutionsAreRetina() {
        for resolution in StageResolution.all {
            XCTAssertEqual(resolution.pointWidth * 2, resolution.pixelWidth)
            XCTAssertEqual(resolution.pointHeight * 2, resolution.pixelHeight)
        }
        XCTAssertEqual(StageResolution.named("2560x1440"), StageResolution(pixelWidth: 2560, pixelHeight: 1440))
        XCTAssertEqual(StageResolution.maximumPixelSize, CGSize(width: 3840, height: 2160))
    }
}
