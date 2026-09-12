import CoreGraphics
import XCTest
@testable import DioramaCore

final class WallpaperClickGuardTests: XCTestCase {
    func testWallpaperClickConsumesBothDownAndUp() {
        var guardrail = WallpaperClickGuard()
        XCTAssertTrue(guardrail.consumes(.leftMouseDown, captured: true) { true })
        XCTAssertTrue(guardrail.consumes(.leftMouseUp, captured: true) { false })
        XCTAssertFalse(guardrail.consumes(.leftMouseUp, captured: true) { true })
    }

    func testWallpaperDragCannotLeakIntoAnotherWindowOrPhysicalDisplay() {
        var guardrail = WallpaperClickGuard()
        XCTAssertTrue(guardrail.consumes(.leftMouseDown, captured: true) { true })
        XCTAssertTrue(guardrail.consumes(.leftMouseDragged, captured: true) { false })
        XCTAssertTrue(guardrail.consumes(.leftMouseDragged, captured: false) { false })
        XCTAssertTrue(guardrail.consumes(.leftMouseUp, captured: false) { false })
        XCTAssertFalse(guardrail.consumes(.leftMouseDown, captured: false) { true })
    }

    func testPhysicalDesktopClicksAreUntouchedAndDoNotHitTest() {
        var guardrail = WallpaperClickGuard()
        XCTAssertFalse(guardrail.consumes(.leftMouseDown, captured: false) {
            XCTFail("A physical-screen click must not query or filter its target")
            return true
        })
        XCTAssertFalse(guardrail.consumes(.leftMouseUp, captured: false) { true })
    }

    func testAppMenuAndDockGesturesPassThroughEvenWhenEndingOnWallpaper() {
        var guardrail = WallpaperClickGuard()
        XCTAssertFalse(guardrail.consumes(.leftMouseDown, captured: true) { false })
        XCTAssertFalse(guardrail.consumes(.leftMouseDragged, captured: true) { true })
        XCTAssertFalse(guardrail.consumes(.leftMouseUp, captured: true) { true })
    }

    func testSecondaryClicksScrollAndMovementPassThrough() {
        var guardrail = WallpaperClickGuard()
        for type: CGEventType in [.rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel, .mouseMoved] {
            XCTAssertFalse(guardrail.consumes(type, captured: true) {
                XCTFail("Only the primary down needs a wallpaper hit test")
                return true
            })
        }
    }

    func testAppClickWorksAfterWallpaperGestureFinishes() {
        var guardrail = WallpaperClickGuard()
        XCTAssertTrue(guardrail.consumes(.leftMouseDown, captured: true) { true })
        XCTAssertTrue(guardrail.consumes(.leftMouseUp, captured: true) { true })
        XCTAssertFalse(guardrail.consumes(.leftMouseDown, captured: true) { false })
        XCTAssertFalse(guardrail.consumes(.leftMouseUp, captured: true) { false })
    }

    func testControlClickPreservesTheDesktopContextMenu() {
        var guardrail = WallpaperClickGuard()
        XCTAssertFalse(guardrail.consumes(.leftMouseDown, captured: true, flags: .maskControl) {
            XCTFail("A context click must not be blocked")
            return true
        })
        XCTAssertFalse(guardrail.consumes(.leftMouseUp, captured: true) { true })
    }
}
