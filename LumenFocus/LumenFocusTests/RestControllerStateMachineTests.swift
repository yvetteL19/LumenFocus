//
//  RestControllerStateMachineTests.swift
//  LumenFocusTests
//
//  Verifies the rest stage transitions purely from time-elapsed inputs.
//

import XCTest
import Combine
@testable import LumenFocus

final class RestControllerStateMachineTests: XCTestCase {
    var controller: RestController!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        controller = RestController.shared
        controller._testReset()
        cancellables = []
    }

    override func tearDown() {
        controller._testReset()
        cancellables = nil
        super.tearDown()
    }

    /// 一次 5 分钟（300s）休息：tickRest 推进各阶段
    func test_fiveMinuteRest_transitionsThroughAllStages() {
        var observed: [RestStage] = []
        controller.stage
            .sink { observed.append($0) }
            .store(in: &cancellables)

        controller.beginRest(duration: 300)
        XCTAssertEqual(controller.stage.value, .fadingIn)

        controller.tickRest(elapsed: 10)
        XCTAssertEqual(controller.stage.value, .fadingIn, "0~20s 内仍应为 fadingIn")

        controller.tickRest(elapsed: 20)
        XCTAssertEqual(controller.stage.value, .midRest, "elapsed=20s 应进入 midRest")

        controller.tickRest(elapsed: 279)
        XCTAssertEqual(controller.stage.value, .midRest, "remaining=21s 仍应为 midRest")

        controller.tickRest(elapsed: 281)
        XCTAssertEqual(controller.stage.value, .fadingOut, "remaining=19s 应进入 fadingOut")

        // 自然完成
        controller.completeRest()
        XCTAssertEqual(controller.stage.value, .idle)

        // 至少应包含 idle → fadingIn → midRest → fadingOut → idle 五个值
        XCTAssertTrue(observed.contains(.fadingIn))
        XCTAssertTrue(observed.contains(.midRest))
        XCTAssertTrue(observed.contains(.fadingOut))
    }

    func test_cancelDuringFadeIn_endsImmediately() {
        let exp = expectation(description: "didFinish should fire")
        controller.didFinish
            .sink { reason in
                XCTAssertEqual(reason, .userCancelled)
                exp.fulfill()
            }
            .store(in: &cancellables)

        controller.beginRest(duration: 300)
        XCTAssertEqual(controller.stage.value, .fadingIn)

        controller.cancelRest()
        XCTAssertEqual(controller.stage.value, .idle)
        wait(for: [exp], timeout: 0.5)
    }

    func test_snooze_onlyValidDuringFadeIn() {
        controller.beginRest(duration: 300)
        XCTAssertEqual(controller.stage.value, .fadingIn)

        var finishedReason: RestEndReason?
        controller.didFinish
            .sink { finishedReason = $0 }
            .store(in: &cancellables)

        controller.snooze(by: 120)
        XCTAssertEqual(controller.stage.value, .idle)
        if case .snoozed(let s) = finishedReason {
            XCTAssertEqual(s, 120)
        } else {
            XCTFail("Expected snoozed reason")
        }

        // 再次进入 midRest，snooze 应被忽略
        controller.beginRest(duration: 300)
        controller.tickRest(elapsed: 30)
        XCTAssertEqual(controller.stage.value, .midRest)

        finishedReason = nil
        controller.snooze(by: 120)
        XCTAssertNil(finishedReason, "midRest 阶段调 snooze 应无效")
        XCTAssertEqual(controller.stage.value, .midRest)
    }

    func test_beginRest_whileAlreadyResting_isIgnored() {
        controller.beginRest(duration: 300)
        controller.beginRest(duration: 999)
        // 第二次调用应被忽略 — duration 仍以第一次为准
        // 走到 280s 时仍应为 fadingOut（300 - 20 = 280 阈值）
        controller.tickRest(elapsed: 281)
        XCTAssertEqual(controller.stage.value, .fadingOut)
    }

    func test_completeRest_whenIdle_isNoop() {
        XCTAssertEqual(controller.stage.value, .idle)

        var didFinishCalled = false
        controller.didFinish
            .sink { _ in didFinishCalled = true }
            .store(in: &cancellables)

        controller.completeRest()
        XCTAssertFalse(didFinishCalled)
    }
}
