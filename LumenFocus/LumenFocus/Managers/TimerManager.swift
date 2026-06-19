//
//  TimerManager.swift
//  LumenFocus
//
//  Owns the work-period heartbeat. Delegates the rest phase entirely to RestController.
//

import Foundation
import Combine

/// 计时管理器 — 工作期心跳，休息期协调
///
/// 不再持有任何 `DispatchQueue.asyncAfter` 兜底，所有状态推进都从 1 秒 tick 派生。
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let appState = AppState.shared
    private let restController = RestController.shared
    private let workspaceMonitor = WorkspaceMonitor.shared

    /// 当前休息从什么时刻起算（用于推进 RestController 的阶段）
    private var restStartedAt: Date?

    /// 进入自动暂停（idle）时的时刻，用于「离开太久则回滚剩余时间」逻辑
    private var autoSuspendedAt: Date?

    var isRunning: Bool { timer?.isValid == true }

    private init() {
        setupSubscriptions()
    }

    // MARK: - Public

    /// 启动工作周期
    func start() {
        stop()
        appState.startWorkCycle()
        scheduleHeartbeat()
    }

    /// 完全停止心跳
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 用户主动暂停
    func pause(duration: TimeInterval? = nil) {
        appState.pause(duration: duration)
        stop()
    }

    /// 恢复
    func resume() {
        start()
    }

    /// 手动触发立即休息（用于开发菜单、全局快捷键、Onboarding 试用按钮）
    func triggerManualRest() {
        guard appState.isWorking else {
            Log.timer.warning("triggerManualRest called outside .working; ignored")
            return
        }
        Log.timer.info("Manual rest triggered")
        if !isRunning { scheduleHeartbeat() }
        startRestPeriod()
    }

    /// 渐暗蒙层「再撑 N 秒」按钮入口
    func snoozeCurrentTrigger(by seconds: TimeInterval) {
        restController.snooze(by: seconds)
    }

    // MARK: - Deprecated shim

    @available(*, deprecated, renamed: "triggerManualRest")
    func triggerTestRest() {
        triggerManualRest()
    }

    @available(*, deprecated, message: "RestController owns rest cancellation; call RestController.shared.cancelRest()")
    func cancelRest() {
        restController.cancelRest()
    }

    // MARK: - Private

    private func setupSubscriptions() {
        // 休息结束 → 回到工作周期 / snooze 回写
        restController.didFinish
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reason in
                self?.handleRestFinished(reason: reason)
            }
            .store(in: &cancellables)

        // 用户主动暂停时停心跳
        appState.$currentPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                if case .paused(let until) = phase {
                    self?.handleUserPause(until: until)
                }
            }
            .store(in: &cancellables)

        // 环境感知：自动避让
        if AppSettings.shared.enableSmartDetection {
            subscribeToWorkspaceSignals()
        }
    }

    private func subscribeToWorkspaceSignals() {
        workspaceMonitor.pauseSignal
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                self?.handleWorkspaceSignal(signal)
            }
            .store(in: &cancellables)
    }

    private func handleWorkspaceSignal(_ signal: PauseSignal?) {
        switch (appState.currentPhase, signal) {
        case (.working, .some(let s)):
            Log.timer.info("Auto-suspend triggered: \(String(describing: s.reason), privacy: .public)")
            autoSuspendedAt = Date()
            appState.autoSuspend(reason: s.reason)
            stop()

        case (.autoSuspended, .none):
            Log.timer.info("Auto-suspend lifted; resuming work")
            applyIdleRollbackIfNeeded()
            autoSuspendedAt = nil
            appState.resumeFromAutoSuspend()
            scheduleHeartbeat()

        case (.autoSuspended(let current), .some(let s)) where current != s.reason:
            // 一种避让原因切换到另一种（idle → videoCall）— 更新 reason 但不重置时刻
            appState.currentPhase = .autoSuspended(reason: s.reason)

        default:
            break
        }
    }

    /// 自动暂停超过当前工作周期一半时长时，认为用户「真的离开了」，回滚剩余时间到满
    private func applyIdleRollbackIfNeeded() {
        guard let suspendedAt = autoSuspendedAt else { return }
        let suspendedDuration = Date().timeIntervalSince(suspendedAt)
        let halfWorkPeriod = TimeInterval(AppSettings.shared.workDurationMinutes * 60) / 2
        if suspendedDuration >= halfWorkPeriod {
            Log.timer.info("Auto-suspend lasted \(suspendedDuration, format: .fixed(precision: 0))s ≥ 50% of work period; resetting remainingSeconds to full")
            appState.remainingSeconds = AppSettings.shared.workDurationMinutes * 60
        }
    }

    private func scheduleHeartbeat() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer { RunLoop.current.add(t, forMode: .common) }
    }

    private func tick() {
        switch appState.currentPhase {
        case .working:
            tickWorking()
        case .triggeringRest, .resting:
            tickResting()
        case .paused, .autoSuspended:
            break
        }
    }

    private func tickWorking() {
        appState.recordWorkDuration()
        if appState.remainingSeconds > 0 {
            appState.remainingSeconds -= 1
            appState.updateProgress()
        } else {
            startRestPeriod()
        }
    }

    private func tickResting() {
        if appState.remainingSeconds > 0 {
            appState.remainingSeconds -= 1
            appState.updateProgress()
            if let start = restStartedAt {
                restController.tickRest(elapsed: Date().timeIntervalSince(start))
            }
        } else {
            restController.completeRest()
        }
    }

    private func startRestPeriod() {
        let duration = TimeInterval(AppSettings.shared.restDurationMinutes * 60)
        restStartedAt = Date()
        restController.beginRest(duration: duration)
    }

    private func handleRestFinished(reason: RestEndReason) {
        restStartedAt = nil
        switch reason {
        case .completed:
            appState.completeRest()
        case .userCancelled:
            appState.cancelRest()
        case .snoozed(let seconds):
            appState.startWorkCycle()
            appState.remainingSeconds = Int(seconds)
            appState.updateProgress()
        }
    }

    private func handleUserPause(until: PauseEndTime) {
        stop()
        let resumeDate: Date
        switch until {
        case .duration(let date):
            resumeDate = date
        case .endOfDay:
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
            resumeDate = calendar.startOfDay(for: tomorrow)
        }
        let delay = resumeDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.resume()
        }
    }
}
