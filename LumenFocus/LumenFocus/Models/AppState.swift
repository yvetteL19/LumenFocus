//
//  AppState.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//

import Foundation
import Combine

/// 应用状态枚举
enum AppPhase: Equatable {
    /// 正常工作期
    case working
    /// 触发休息（屏幕开始渐变）
    case triggeringRest
    /// 休息进行中
    case resting
    /// 用户主动暂停（勿扰模式）
    case paused(until: PauseEndTime)
    /// 由智能感知自动暂停（不同于用户主动暂停：菜单栏显示不同图标，恢复后无需用户操作）
    case autoSuspended(reason: AutoSuspendReason)
}

/// 暂停结束时间
enum PauseEndTime: Equatable {
    /// 暂停1小时
    case duration(Date)
    /// 暂停至今日结束
    case endOfDay
}

/// 自动暂停的原因
enum AutoSuspendReason: Equatable {
    /// 长时间无键鼠输入
    case idle
    /// 前台是全屏应用
    case fullscreen
    /// 检测到视频通话 / 屏幕共享
    case videoCall
    /// 系统进入勿扰或 Focus Mode
    case focusMode
    /// 屏幕锁定
    case screenLocked
}

/// 应用状态管理器 - 管理应用运行时状态
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published Properties

    /// 当前阶段
    @Published var currentPhase: AppPhase = .working

    /// 剩余秒数（工作期或休息期）
    @Published var remainingSeconds: Int = 0

    /// 进度百分比（0.0 - 1.0）
    @Published var progress: Double = 1.0

    /// 今日已护眼次数
    @Published var todayRestCount: Int = 0

    /// 今日累计用眼时长（秒）
    @Published var todayWorkDuration: Int = 0

    // MARK: - Computed Properties

    /// 是否处于用户主动暂停状态
    var isPaused: Bool {
        if case .paused = currentPhase {
            return true
        }
        return false
    }

    /// 是否处于自动避让暂停
    var isAutoSuspended: Bool {
        if case .autoSuspended = currentPhase {
            return true
        }
        return false
    }

    /// 是否处于任意非工作、非休息状态（用户主动暂停 + 自动避让）
    var isSuspended: Bool {
        isPaused || isAutoSuspended
    }

    /// 是否处于工作期
    var isWorking: Bool {
        currentPhase == .working
    }

    /// 是否处于休息期
    var isResting: Bool {
        currentPhase == .resting || currentPhase == .triggeringRest
    }

    /// 格式化剩余时间（M:SS）
    var formattedRemainingTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 格式化今日用眼时长（本地化）
    var formattedTodayWorkDuration: String {
        formatWorkDuration(todayWorkDuration)
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        loadTodayStatistics()
        startDayResetTimer()
    }

    // MARK: - Public Methods

    /// 开始工作周期
    func startWorkCycle() {
        let settings = AppSettings.shared
        remainingSeconds = settings.workDurationMinutes * 60
        currentPhase = .working
        updateProgress()
    }

    /// 开始休息周期
    func startRestCycle() {
        let settings = AppSettings.shared
        remainingSeconds = settings.restDurationMinutes * 60
        currentPhase = .triggeringRest
        updateProgress()
    }

    /// 完成休息
    func completeRest() {
        todayRestCount += 1
        saveTodayStatistics()
        // 同步到StatisticsManager
        StatisticsManager.shared.incrementTodayRestCount()
        startWorkCycle()
    }

    /// 取消休息（ESC退出）
    func cancelRest() {
        startWorkCycle()
    }

    /// 暂停护眼（勿扰模式）
    func pause(duration: TimeInterval? = nil) {
        if let duration = duration {
            let endDate = Date().addingTimeInterval(duration)
            currentPhase = .paused(until: .duration(endDate))
        } else {
            currentPhase = .paused(until: .endOfDay)
        }
    }

    /// 恢复护眼
    func resume() {
        startWorkCycle()
    }

    /// 更新进度百分比
    func updateProgress() {
        let settings = AppSettings.shared
        let totalSeconds: Int

        switch currentPhase {
        case .working:
            totalSeconds = settings.workDurationMinutes * 60
        case .resting, .triggeringRest:
            totalSeconds = settings.restDurationMinutes * 60
        case .paused, .autoSuspended:
            progress = 0.0
            return
        }

        progress = Double(remainingSeconds) / Double(totalSeconds)
    }

    /// 进入自动暂停（智能感知）
    func autoSuspend(reason: AutoSuspendReason) {
        guard !isAutoSuspended else { return }
        currentPhase = .autoSuspended(reason: reason)
    }

    /// 解除自动暂停，回到工作周期。
    /// 不重置 `remainingSeconds` — 由 `TimerManager.applyIdleRollbackIfNeeded()` 决定是否回滚
    func resumeFromAutoSuspend() {
        guard isAutoSuspended else { return }
        currentPhase = .working
        updateProgress()
    }

    /// 记录用眼时长（每秒调用）
    func recordWorkDuration() {
        if case .working = currentPhase {
            todayWorkDuration += 1
            // 同步到StatisticsManager
            StatisticsManager.shared.incrementTodayWorkDuration(seconds: 1)
        }
    }

    // MARK: - Private Methods

    /// 加载今日统计数据
    private func loadTodayStatistics() {
        let todayKey = getTodayKey()
        todayRestCount = UserDefaults.standard.integer(forKey: "restCount_\(todayKey)")
        todayWorkDuration = UserDefaults.standard.integer(forKey: "workDuration_\(todayKey)")
    }

    /// 保存今日统计数据（内部方法）
    func saveTodayStatistics() {
        let todayKey = getTodayKey()
        UserDefaults.standard.set(todayRestCount, forKey: "restCount_\(todayKey)")
        UserDefaults.standard.set(todayWorkDuration, forKey: "workDuration_\(todayKey)")
        // 同步给 Widget
        let stats = StatisticsManager.shared
        SharedDataAccess.writeTodaySnapshot(
            restCount: todayRestCount,
            workSeconds: todayWorkDuration,
            currentStreak: stats.getCurrentStreak(),
            weeklyBars: stats.getWeeklyStatistics().map(\.restCount)
        )
    }

    /// 获取今日的Key（格式：yyyy-MM-dd）
    func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 启动每日重置定时器（午夜重置统计）
    private func startDayResetTimer() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkDayChange()
            }
            .store(in: &cancellables)
    }

    /// 检查日期变化
    private func checkDayChange() {
        let currentKey = getTodayKey()
        let lastKey = UserDefaults.standard.string(forKey: "lastCheckedDay") ?? ""

        if currentKey != lastKey {
            // 新的一天，重置统计
            todayRestCount = 0
            todayWorkDuration = 0
            UserDefaults.standard.set(currentKey, forKey: "lastCheckedDay")
        }
    }
}
