import XCTest
@testable import DioramaCore

final class StageWindowPlacementTests: XCTestCase {
    let physical = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let virtual = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testOrdinaryPlacementAndSpanningPhysicalMonitorsArePreserved() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        for frame in [CGRect(x: 100, y: 100, width: 800, height: 600),
                      CGRect(x: -400, y: 100, width: 800, height: 600),
                      CGRect(x: 640, y: 100, width: 800, height: 600)] {
            XCTAssertEqual(StageWindowPlacement.constrain(frame, virtualBounds: virtual, physicalBounds: [physical, left]), frame)
        }
    }

    func testPartialOverlapIsRemovedOnEverySide() {
        let layouts = [
            (CGRect(x: 1440, y: 0, width: 1920, height: 1080), CGRect(x: 1000, y: 100, width: 800, height: 600)),
            (CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: -100, y: 100, width: 800, height: 600)),
            (CGRect(x: 0, y: 900, width: 1920, height: 1080), CGRect(x: 100, y: 500, width: 800, height: 600)),
            (CGRect(x: 0, y: -1080, width: 1920, height: 1080), CGRect(x: 100, y: -100, width: 800, height: 600))
        ]
        for (display, frame) in layouts {
            let result = StageWindowPlacement.constrain(frame, virtualBounds: display, physicalBounds: [physical])
            XCTAssertTrue(physical.contains(result))
            XCTAssertFalse(display.intersects(result))
            XCTAssertEqual(result.size, frame.size)
            XCTAssertEqual(StageWindowPlacement.constrain(result, virtualBounds: display, physicalBounds: [physical]), result)
        }
    }

    func testWindowRestoredEntirelyInsideVirtualDisplayReturnsToPhysicalScreen() {
        let frame = CGRect(x: 1900, y: 200, width: 800, height: 600)
        XCTAssertEqual(StageWindowPlacement.constrain(frame, virtualBounds: virtual, physicalBounds: [physical]),
                       CGRect(x: 640, y: 200, width: 800, height: 600))
    }

    func testRescuePrefersPhysicalMonitorWithMostOverlap() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let upperVirtual = CGRect(x: -1440, y: 900, width: 2880, height: 1080)
        let frame = CGRect(x: -600, y: 600, width: 800, height: 600)
        let result = StageWindowPlacement.constrain(frame, virtualBounds: upperVirtual, physicalBounds: [physical, left])
        XCTAssertEqual(result, CGRect(x: -800, y: 300, width: 800, height: 600))
    }

    func testOffscreenRescueUsesNearestPhysicalMonitorAndFitsOversizedWindow() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -1600, y: 2000, width: 1600, height: 1000)
        XCTAssertEqual(StageWindowPlacement.constrain(frame, virtualBounds: virtual, physicalBounds: [physical, left]), left)
    }

    func testDisplayReconfigurationCanRescuePreviouslyPhysicalWindow() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let newPhysical = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let result = StageWindowPlacement.constrain(frame, virtualBounds: physical, physicalBounds: [newPhysical])
        XCTAssertTrue(newPhysical.contains(result))
        XCTAssertFalse(physical.intersects(result))
    }

    func testIncompleteDisplayConfigurationDoesNotInventPlacement() {
        let frame = CGRect(x: 1800, y: 100, width: 800, height: 600)
        XCTAssertEqual(StageWindowPlacement.constrain(frame, virtualBounds: virtual, physicalBounds: []), frame)
        XCTAssertEqual(StageWindowPlacement.constrain(frame, virtualBounds: .zero, physicalBounds: [physical]), frame)
    }
}
