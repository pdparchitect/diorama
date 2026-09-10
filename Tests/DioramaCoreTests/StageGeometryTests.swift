import XCTest
@testable import DioramaCore

final class StageGeometryTests: XCTestCase {
    func testFitLetterboxesWideContentInTallContainer() {
        let fitted = StageGeometry.fit(CGSize(width: 1920, height: 1080), in: CGRect(x: 100, y: 100, width: 960, height: 960))
        XCTAssertEqual(fitted, CGRect(x: 100, y: 310, width: 960, height: 540))
    }

    func testFitPillarboxesTallContentInWideContainer() {
        let fitted = StageGeometry.fit(CGSize(width: 1000, height: 1000), in: CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertEqual(fitted, CGRect(x: 100, y: 0, width: 200, height: 200))
    }

    func testFitRejectsDegenerateSizes() {
        XCTAssertEqual(StageGeometry.fit(.zero, in: CGRect(x: 0, y: 0, width: 10, height: 10)), .zero)
        XCTAssertEqual(StageGeometry.fit(CGSize(width: 1, height: 1), in: .zero), .zero)
    }

    func testMapsBetweenStageAndDisplay() {
        let geometry = StageGeometry(stage: CGRect(x: 100, y: 200, width: 960, height: 540), display: CGRect(x: 1728, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(geometry.scale, 2)
        XCTAssertEqual(geometry.toDisplay(CGPoint(x: 100, y: 200)), CGPoint(x: 1728, y: 0))
        XCTAssertEqual(geometry.toDisplay(CGPoint(x: 580, y: 470)), CGPoint(x: 2688, y: 540))
        XCTAssertEqual(geometry.toStage(CGPoint(x: 2688, y: 540)), CGPoint(x: 580, y: 470))
    }

    func testClampKeepsPointsInsideHalfOpenRect() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(Clamp.point(CGPoint(x: 150, y: -5), into: rect), CGPoint(x: 99, y: 0))
        XCTAssertEqual(Clamp.point(CGPoint(x: 10, y: 10), into: rect), CGPoint(x: 10, y: 10))
    }

    func testClampPicksNearestRect() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 300, y: 0, width: 100, height: 100)
        XCTAssertEqual(Clamp.point(CGPoint(x: 120, y: 50), intoAnyOf: [left, right]), CGPoint(x: 99, y: 50))
        XCTAssertEqual(Clamp.point(CGPoint(x: 280, y: 50), intoAnyOf: [left, right]), CGPoint(x: 300, y: 50))
        XCTAssertEqual(Clamp.point(CGPoint(x: 5, y: 5), intoAnyOf: []), CGPoint(x: 5, y: 5))
    }
}
