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
