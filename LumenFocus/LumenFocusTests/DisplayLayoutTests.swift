import XCTest
@testable import LumenFocus

final class DisplayLayoutTests: XCTestCase {
    private func screen(_ id: UInt32, _ frame: CGRect) -> DisplayLayout.Screen {
        .init(id: id, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 24))
    }

    func testNegativeCoordinateDisplayUsesLocalPointBounds() {
        let left = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
        XCTAssertEqual(DisplayLayout.contentBounds(for: left), CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let plan = DisplayLayout.update(existingFrames: [:], screens: [screen(1, .init(x: 0, y: 0, width: 1440, height: 900)), screen(2, left)],
                                        retaining: nil, pointer: CGPoint(x: -500, y: 200))
        XCTAssertEqual(plan.primaryID, 2)
        XCTAssertEqual(plan.insertedIDs, [1, 2])
    }

    func testRetinaLogicalFrameIsNotMultipliedByPixelDensity() {
        // A 2880×1800 backing surface has a 1440×900 point frame. The adjacent
        // 1× display still uses its own point frame, with no shared scale factor.
        let retina = screen(1, CGRect(x: 0, y: 0, width: 1440, height: 900))
        let external = screen(2, CGRect(x: 1440, y: -180, width: 1920, height: 1080))
        let plan = DisplayLayout.update(existingFrames: [:], screens: [retina, external],
                                        retaining: nil, pointer: CGPoint(x: 1600, y: 0))
        XCTAssertEqual(plan.primaryID, 2)
        XCTAssertEqual(DisplayLayout.contentBounds(for: retina.frame).width, 1440)
        XCTAssertEqual(DisplayLayout.contentBounds(for: external.frame).width, 1920)
    }

    func testRearrangingOrChangingResolutionReusesTheSameDisplayWindow() {
        let old = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let changed = screen(7, CGRect(x: 0, y: 900, width: 1280, height: 720))
        let plan = DisplayLayout.update(existingFrames: [7: old], screens: [changed], retaining: 7, pointer: .zero)
        XCTAssertEqual(plan.resizedIDs, [7])
        XCTAssertTrue(plan.insertedIDs.isEmpty)
        XCTAssertTrue(plan.removedIDs.isEmpty)
        XCTAssertEqual(plan.primaryID, 7)
    }

    func testHotplugRetainsPrimaryAndUnaffectedWindowsDespitePointerMovement() {
        let first = screen(1, CGRect(x: 0, y: 0, width: 1440, height: 900))
        let added = screen(2, CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let plan = DisplayLayout.update(existingFrames: [1: first.frame], screens: [first, added],
                                        retaining: 1, pointer: CGPoint(x: -800, y: 400))
        XCTAssertEqual(plan.primaryID, 1)
        XCTAssertEqual(plan.insertedIDs, [2])
        XCTAssertTrue(plan.resizedIDs.isEmpty)
        XCTAssertTrue(plan.removedIDs.isEmpty)
    }

    func testRemovingPrimaryChoosesASurvivingDisplayAndRemovesOnlyTheMissingOne() {
        let first = screen(1, CGRect(x: 0, y: 0, width: 1440, height: 900))
        let second = screen(2, CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        let plan = DisplayLayout.update(existingFrames: [1: first.frame, 2: second.frame], screens: [second],
                                        retaining: 1, pointer: .zero)
        XCTAssertEqual(plan.primaryID, 2)
        XCTAssertEqual(plan.removedIDs, [1])
        XCTAssertTrue(plan.insertedIDs.isEmpty)
    }

    func testNoDisplaysProducesCleanupWithoutAKeyWindowTarget() {
        let plan = DisplayLayout.update(existingFrames: [1: CGRect(x: 0, y: 0, width: 1440, height: 900)],
                                        screens: [], retaining: 1, pointer: .zero)
        XCTAssertNil(plan.primaryID)
        XCTAssertEqual(plan.removedIDs, [1])
    }

}
