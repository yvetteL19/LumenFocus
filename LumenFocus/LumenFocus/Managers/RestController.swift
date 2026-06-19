//
//  RestController.swift
//  LumenFocus
//
//  Single source of truth for the rest lifecycle.
//  Owns the rest stage state machine; TimerManager drives ticks; RestManager renders.
//

import Foundation
import Combine

/// 休息流程的具体阶段。所有阶段从已用时长派生，不依赖独立计时器
enum RestStage: Equatable {
    /// 不在休息中
    case idle
    /// 渐暗中（0 ~ fadeInDuration）
    case fadingIn
    /// 主体休息阶段（中段进一步细分为 `MidRestActivity`）
    case midRest
    /// 渐亮中（最后 fadeOutDuration）
    case fadingOut
}

/// midRest 阶段进一步细分的引导活动
enum MidRestActivity: Equatable {
    /// 呼吸节律（midRest 前 50%）
    case breathing
    /// 远焦点训练（midRest 50%~75%）
    case farFocus
    /// 自由休息 + 文字 tip（midRest 最后 25%）
    case free
}

/// 休息为何结束
enum RestEndReason: Equatable {
    /// 自然走完
    case completed
    /// 用户按 ESC 中止
    case userCancelled
    /// 用户在渐暗早期点了「再撑 2 分钟」
    case snoozed(seconds: TimeInterval)
}

/// 休息流程控制器。
///
/// 职责：
/// - 持有当前 `RestStage` 状态机；由 `TimerManager.tickRest(elapsed:)` 推进
/// - 维护 `AppState.currentPhase` 在 `.triggeringRest` ↔ `.resting` 间的翻转
/// - 通过 Combine publisher 通知 `RestManager` 渲染层
/// - 处理 ESC 取消、snooze、自然完成三种终止路径
///
/// 不持有定时器，避免与 `TimerManager` 的心跳产生二个时间源。
final class RestController {
    static let shared = RestController()

    // MARK: - Constants

    /// 渐暗动画时长
    static let fadeInDuration: TimeInterval = 20

    /// 渐亮动画时长（最后多少秒开始 fade-out）
    static let fadeOutDuration: TimeInterval = 20

    // MARK: - Published State

    /// 当前阶段。`RestManager` 订阅此 publisher 决定窗口与动画
    let stage: CurrentValueSubject<RestStage, Never> = .init(.idle)

    /// midRest 内的引导活动。`RestOverlayWindow` 主屏订阅此切换 SwiftUI 子视图
    let midRestActivity: CurrentValueSubject<MidRestActivity, Never> = .init(.breathing)

    /// 休息结束事件流。`TimerManager` 订阅此以回到工作周期
    let didFinish: PassthroughSubject<RestEndReason, Never> = .init()

    // MARK: - Private

    private let appState = AppState.shared
    private var totalDuration: TimeInterval = 0

    private init() {}

    #if DEBUG
    /// 测试用：把状态机重置为 idle，并清空发布的最后值（不影响 AppState）
    func _testReset() {
        totalDuration = 0
        stage.send(.idle)
    }
    #endif

    // MARK: - Public API

    /// 进入休息周期。由 `TimerManager` 在工作期归零时调用。
    /// - Parameter duration: 完整休息时长（含渐暗渐亮）
    func beginRest(duration: TimeInterval) {
        guard stage.value == .idle else {
            Log.rest.warning("beginRest called while stage is \(String(describing: self.stage.value), privacy: .public); ignored")
            return
        }
        Log.rest.info("Rest started, total=\(duration, format: .fixed(precision: 0))s")
        totalDuration = duration
        midRestActivity.send(.breathing)
        appState.startRestCycle()
        AmbientSoundManager.shared.play(AppSettings.shared.ambientTrack)
        // startRestCycle 将 currentPhase 设为 .triggeringRest，remainingSeconds 设为 restDurationMinutes * 60
        updateStage(forElapsed: 0)
    }

    /// 由 `TimerManager.tick` 在每秒推进后调用，传入相对 begin 的已用秒数。
    func tickRest(elapsed: TimeInterval) {
        guard stage.value != .idle else { return }
        updateStage(forElapsed: elapsed)
    }

    /// 用户按 ESC 取消休息
    func cancelRest() {
        guard stage.value != .idle else { return }
        Log.rest.info("Rest cancelled by user")
        finish(reason: .userCancelled)
    }

    /// 倒计时自然归零
    func completeRest() {
        guard stage.value != .idle else { return }
        Log.rest.info("Rest completed naturally")
        finish(reason: .completed)
    }

    /// 渐暗早期点了「再撑 N 秒」
    /// - Parameter seconds: 推迟多久后再触发下一次休息（用于回写工作期 remainingSeconds）
    func snooze(by seconds: TimeInterval) {
        guard case .fadingIn = stage.value else {
            Log.rest.warning("snooze called outside fadingIn; ignored")
            return
        }
        Log.rest.info("Rest snoozed by \(seconds, format: .fixed(precision: 0))s")
        finish(reason: .snoozed(seconds: seconds))
    }

    /// 演示模式：按压缩时长跑一遍渐暗→中段→渐亮，用于 Onboarding。
    /// M2 实装；此处仅占位，使后续编译通过。
    func runDemoSequence(duration: TimeInterval = 10) {
        // TODO(M2): 旁路一个临时计时器，跑完整 5 阶段的压缩版
        Log.rest.debug("runDemoSequence stub called (duration=\(duration)s)")
    }

    // MARK: - Private

    private func updateStage(forElapsed elapsed: TimeInterval) {
        let remaining = totalDuration - elapsed
        let next: RestStage

        if elapsed < Self.fadeInDuration {
            next = .fadingIn
        } else if remaining > Self.fadeOutDuration {
            next = .midRest
            updateMidRestActivity(forElapsed: elapsed)
        } else {
            next = .fadingOut
        }

        guard next != stage.value else { return }

        Log.rest.debug("Stage \(String(describing: self.stage.value), privacy: .public) → \(String(describing: next), privacy: .public)")
        stage.send(next)

        // 进入 midRest 时把 currentPhase 升格为 .resting，让外部观察者（菜单栏图标等）知道渐暗已完成
        if next == .midRest && appState.currentPhase == .triggeringRest {
            appState.currentPhase = .resting
        }
    }

    /// midRest 引导切换的最短窗口。短于此值则全程呼吸，避免各活动只闪现几秒。
    private static let minSegmentedMidDuration: TimeInterval = 90

    /// 在 midRest 阶段细分子活动：前 50% 呼吸 → 25% 远焦点 → 25% 自由。
    /// 当 midRest 窗口较短（如 20-20-20 的 1 分钟休息）时，全程保持呼吸，
    /// 避免远焦点 / 自由活动只闪现几秒带来的割裂感。
    private func updateMidRestActivity(forElapsed elapsed: TimeInterval) {
        let midStart = Self.fadeInDuration
        let midEnd = totalDuration - Self.fadeOutDuration
        let midDuration = midEnd - midStart
        guard midDuration > 0 else { return }

        let next: MidRestActivity
        if midDuration < Self.minSegmentedMidDuration {
            next = .breathing
        } else {
            let ratio = (elapsed - midStart) / midDuration
            if ratio < 0.5 {
                next = .breathing
            } else if ratio < 0.75 {
                next = .farFocus
            } else {
                next = .free
            }
        }

        if next != midRestActivity.value {
            Log.rest.debug("MidRestActivity \(String(describing: self.midRestActivity.value), privacy: .public) → \(String(describing: next), privacy: .public)")
            midRestActivity.send(next)
        }
    }

    private func finish(reason: RestEndReason) {
        totalDuration = 0
        stage.send(.idle)
        midRestActivity.send(.breathing)  // 重置以便下次干净开始
        AmbientSoundManager.shared.stop()
        didFinish.send(reason)
    }
}
