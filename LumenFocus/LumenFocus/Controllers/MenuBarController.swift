//
//  MenuBarController.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//

import Cocoa
import Combine
import SwiftUI

/// 菜单栏控制器 - 管理菜单栏图标和交互
class MenuBarController: NSObject {
    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private let appState = AppState.shared
    private let settings = AppSettings.shared
    private let iconManager = IconManager.shared
    private var cancellables = Set<AnyCancellable>()

    /// 图标状态
    private enum IconState {
        case full           // 满格 (100%-67%)
        case half           // 半格 (66%-34%)
        case low            // 低电 (33%-1%)
        case paused         // 用户主动暂停
        case autoSuspended  // 智能避让自动暂停
    }

    private var currentIconState: IconState = .full
    private var flashTimer: Timer?

    /// 左键点击弹出的 SwiftUI popover
    private var popover: NSPopover?

    // MARK: - Initialization

    func setup() {
        // 创建状态栏项目
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 配置 button：左键 → popover；右键 → 上下文菜单
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 设置初始图标
        updateIcon()

        // 预备 popover
        setupPopover()

        // 监听状态变化
        setupObservers()
    }

    // MARK: - Popover

    private func setupPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 320, height: 440)

        let view = MenuBarPopoverView(onClose: { [weak self] in
            self?.popover?.performClose(nil)
        })
        pop.contentViewController = NSHostingController(rootView: view)
        popover = pop
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 激活以便 hover 状态等正常工作
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        if appState.isPaused {
            setupPausedMenu(menu)
        } else {
            setupNormalMenu(menu)
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // 弹完后立即清空，避免左键也走菜单
        statusItem?.menu = nil
    }

    // MARK: - Private Methods

    /// 更新菜单栏图标
    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        // 根据状态更新图标（iconState 仍用于 tooltip 文案分级）
        let iconState = determineIconState()
        let iconImage: NSImage

        switch iconState {
        case .full, .half, .low:
            // 连续进度环，精确反映剩余比例
            iconImage = iconManager.progressIcon(appState.progress)
        case .paused:
            iconImage = iconManager.pausedIcon()
        case .autoSuspended:
            iconImage = iconManager.pausedIcon()
            // 自动暂停时图标半透明，与用户主动暂停做视觉区分
            button.alphaValue = 0.55
        }

        button.image = iconImage
        button.imagePosition = .imageLeading
        if iconState != .autoSuspended { button.alphaValue = 1.0 }

        // 菜单栏剩余分钟数字（设置开关）
        if settings.showRemainingMinutesInMenuBar, appState.isWorking, appState.remainingSeconds > 0 {
            let minutes = Swift.max(1, Int(ceil(Double(appState.remainingSeconds) / 60)))
            button.title = "  \(minutes)m"
        } else {
            button.title = ""
        }

        // 设置辅助功能标签
        button.toolTip = createTooltip(for: iconState)

        currentIconState = iconState
    }

    /// 确定图标状态
    private func determineIconState() -> IconState {
        if appState.isAutoSuspended {
            return .autoSuspended
        }
        if appState.isPaused {
            return .paused
        }

        let progress = appState.progress

        if progress > 0.67 {
            return .full
        } else if progress > 0.34 {
            return .half
        } else {
            return .low
        }
    }

    /// 创建Tooltip文本
    private func createTooltip(for state: IconState) -> String {
        switch state {
        case .full:
            let minutes = appState.remainingSeconds / 60
            return String(format: L("LumenFocus - 眼睛电量满格，还有%d分钟"), minutes)
        case .half:
            let minutes = appState.remainingSeconds / 60
            return String(format: L("LumenFocus - 眼睛电量一半，还有%d分钟"), minutes)
        case .low:
            let minutes = appState.remainingSeconds / 60
            return String(format: L("LumenFocus - 眼睛电量低，还有%d分钟即将休息"), minutes)
        case .paused:
            if case .paused(let until) = appState.currentPhase {
                switch until {
                case .duration(let date):
                    let remaining = Int(date.timeIntervalSinceNow) / 60
                    return String(format: L("已暂停，剩余 %d 分钟"), remaining)
                case .endOfDay:
                    return L("已暂停至今日结束")
                }
            }
            return L("已暂停")
        case .autoSuspended:
            return tooltipForAutoSuspend()
        }
    }

    private func tooltipForAutoSuspend() -> String {
        guard case .autoSuspended(let reason) = appState.currentPhase else {
            return L("LumenFocus - 已自动暂停")
        }
        switch reason {
        case .idle:         return L("LumenFocus - 已自动暂停（检测到无操作）")
        case .videoCall:    return L("LumenFocus - 已自动暂停（检测到视频通话）")
        case .fullscreen:   return L("LumenFocus - 已自动暂停（检测到全屏应用）")
        case .focusMode:    return L("LumenFocus - 已自动暂停（系统勿扰模式）")
        case .screenLocked: return L("LumenFocus - 已自动暂停（屏幕锁定）")
        }
    }

    /// 设置正常状态菜单
    private func setupNormalMenu(_ menu: NSMenu) {
        // Header - 使用SF Symbol眼睛图标
        let headerItem = NSMenuItem()
        headerItem.attributedTitle = createHeaderTitle()
        if let eyeImage = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "LumenFocus") {
            eyeImage.isTemplate = true
            headerItem.image = eyeImage
        }
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 统计信息区（带背景色）
        let statsView = createStatsView()
        let statsItem = NSMenuItem()
        statsItem.view = statsView
        menu.addItem(statsItem)

        // 粗分割线
        menu.addItem(NSMenuItem.separator())

        // 「稍后提醒」submenu
        let snoozeItem = NSMenuItem(title: L("稍后提醒"), action: nil, keyEquivalent: "")
        if let snoozeImage = NSImage(systemSymbolName: "clock.badge", accessibilityDescription: L("稍后提醒")) {
            snoozeImage.isTemplate = true
            snoozeItem.image = snoozeImage
        }
        snoozeItem.submenu = createSnoozeSubmenu()
        menu.addItem(snoozeItem)

        // 细分割线
        menu.addItem(NSMenuItem.separator())

        // 设置 - 使用SF Symbols
        let settingsItem = NSMenuItem(title: L("设置..."), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("设置")) {
            gearImage.isTemplate = true
            settingsItem.image = gearImage
        }
        menu.addItem(settingsItem)

        // 关于 - 原生标准关于面板
        let aboutItem = NSMenuItem(title: L("关于 LumenFocus"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        if let aboutImage = NSImage(systemSymbolName: "info.circle", accessibilityDescription: L("关于 LumenFocus")) {
            aboutImage.isTemplate = true
            aboutItem.image = aboutImage
        }
        menu.addItem(aboutItem)

#if DEBUG
        // 开发/测试选项 — 仅 Debug 构建可见，不随正式版本上架
        menu.addItem(NSMenuItem.separator())

        let devMenu = NSMenu()

        // 测试休息遮罩
        let testRestItem = NSMenuItem(title: L("测试休息遮罩"), action: #selector(triggerTestRest), keyEquivalent: "t")
        testRestItem.target = self
        if let testImage = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: L("测试")) {
            testImage.isTemplate = true
            testRestItem.image = testImage
        }
        devMenu.addItem(testRestItem)

        // 重新显示欢迎引导
        let showOnboardingItem = NSMenuItem(title: L("重新显示欢迎引导"), action: #selector(resetAndShowOnboarding), keyEquivalent: "")
        showOnboardingItem.target = self
        if let onboardImage = NSImage(systemSymbolName: "hand.wave", accessibilityDescription: L("欢迎")) {
            onboardImage.isTemplate = true
            showOnboardingItem.image = onboardImage
        }
        devMenu.addItem(showOnboardingItem)

        let devMenuItem = NSMenuItem(title: L("开发选项"), action: nil, keyEquivalent: "")
        if let devImage = NSImage(systemSymbolName: "hammer", accessibilityDescription: L("开发")) {
            devImage.isTemplate = true
            devMenuItem.image = devImage
        }
        devMenuItem.submenu = devMenu
        menu.addItem(devMenuItem)
#endif

        menu.addItem(NSMenuItem.separator())

        // 退出 - 使用SF Symbols
        let quitItem = NSMenuItem(title: L("退出"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        if let quitImage = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: L("退出")) {
            quitImage.isTemplate = true
            quitItem.image = quitImage
        }
        menu.addItem(quitItem)
    }

    /// 设置勿扰状态菜单
    private func setupPausedMenu(_ menu: NSMenu) {
        // Header - 使用SF Symbol睡眠图标
        let headerItem = NSMenuItem()
        headerItem.attributedTitle = createPausedHeaderTitle()
        if let sleepImage = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: L("已暂停")) {
            sleepImage.isTemplate = true
            headerItem.image = sleepImage
        }
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 暂停状态信息
        let pauseInfoView = createPauseInfoView()
        let pauseInfoItem = NSMenuItem()
        pauseInfoItem.view = pauseInfoView
        menu.addItem(pauseInfoItem)

        menu.addItem(NSMenuItem.separator())

        // 恢复按钮（黑色加粗）- 使用SF Symbols
        let resumeItem = NSMenuItem(title: L("恢复护眼"), action: #selector(resumeTimer), keyEquivalent: "")
        resumeItem.target = self
        if let playImage = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: L("恢复")) {
            playImage.isTemplate = true
            resumeItem.image = playImage
        }
        // 设置黑色加粗文字
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
        ]
        resumeItem.attributedTitle = NSAttributedString(string: L("恢复护眼"), attributes: attributes)
        menu.addItem(resumeItem)

        menu.addItem(NSMenuItem.separator())

        // 设置 - 使用SF Symbols
        let settingsItem = NSMenuItem(title: L("设置..."), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("设置")) {
            gearImage.isTemplate = true
            settingsItem.image = gearImage
        }
        menu.addItem(settingsItem)

        // 关于 - 原生标准关于面板
        let aboutItem = NSMenuItem(title: L("关于 LumenFocus"), action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        if let aboutImage = NSImage(systemSymbolName: "info.circle", accessibilityDescription: L("关于 LumenFocus")) {
            aboutImage.isTemplate = true
            aboutItem.image = aboutImage
        }
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 退出 - 使用SF Symbols
        let quitItem = NSMenuItem(title: L("退出"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        if let quitImage = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: L("退出")) {
            quitImage.isTemplate = true
            quitItem.image = quitImage
        }
        menu.addItem(quitItem)
    }

    /// 创建Header标题
    private func createHeaderTitle() -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: "LumenFocus", attributes: attributes)
    }

    /// 创建暂停状态Header标题
    private func createPausedHeaderTitle() -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.systemGray
        ]
        return NSAttributedString(string: L("LumenFocus (已暂停)"), attributes: attributes)
    }

    /// 创建统计信息视图
    private func createStatsView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.lumenfocus.backgroundSecondary.cgColor

        // 今日已护眼
        let line1 = NSTextField(labelWithString: String(format: L("今日已护眼：%d 次"), appState.todayRestCount))
        line1.font = NSFont.systemFont(ofSize: 14)
        line1.textColor = .secondaryLabelColor
        line1.frame = NSRect(x: 16, y: 48, width: 248, height: 20)
        view.addSubview(line1)

        // 累计用眼
        let line2 = NSTextField(labelWithString: String(format: L("累计用眼：%@"), appState.formattedTodayWorkDuration))
        line2.font = NSFont.systemFont(ofSize: 14)
        line2.textColor = .secondaryLabelColor
        line2.frame = NSRect(x: 16, y: 28, width: 248, height: 20)
        view.addSubview(line2)

        // 下次休息
        let nextRestMinutes = appState.remainingSeconds / 60
        let line3 = NSTextField(labelWithString: String(format: L("下次休息：%d 分钟后"), nextRestMinutes))
        line3.font = NSFont.systemFont(ofSize: 14)
        line3.textColor = .secondaryLabelColor
        line3.frame = NSRect(x: 16, y: 8, width: 248, height: 20)
        view.addSubview(line3)

        return view
    }

    /// 创建暂停信息视图
    private func createPauseInfoView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.lumenfocus.backgroundSecondary.cgColor

        // 暂停图标
        let pauseIcon = NSImageView(frame: NSRect(x: 16, y: 32, width: 16, height: 16))
        if let pauseImage = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: L("已暂停")) {
            pauseImage.isTemplate = true
            pauseIcon.image = pauseImage
            pauseIcon.contentTintColor = .secondaryLabelColor
        }
        view.addSubview(pauseIcon)

        // 暂停状态文字
        let line1 = NSTextField(labelWithString: L("已暂停"))
        line1.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        line1.textColor = .secondaryLabelColor
        line1.frame = NSRect(x: 36, y: 32, width: 228, height: 20)
        view.addSubview(line1)

        // 剩余时间
        var remainingText = ""
        if case .paused(let until) = appState.currentPhase {
            switch until {
            case .duration(let date):
                let remaining = Int(date.timeIntervalSinceNow) / 60
                remainingText = String(format: L("剩余时间：%d 分钟"), remaining)
            case .endOfDay:
                remainingText = L("暂停至今日结束")
            }
        }

        let line2 = NSTextField(labelWithString: remainingText)
        line2.font = NSFont.systemFont(ofSize: 14)
        line2.textColor = .lumenfocus.textSecondary
        line2.frame = NSRect(x: 16, y: 12, width: 248, height: 20)
        view.addSubview(line2)

        return view
    }


    /// 监听状态变化
    private func setupObservers() {
        // 监听进度变化，更新图标（确保在主线程）
        appState.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        // 监听阶段变化（确保在主线程）
        appState.$currentPhase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.handlePhaseChange(phase)
            }
            .store(in: &cancellables)

        // 休息阶段变化：fadingIn 时开始呼吸闪烁，idle 时停止
        RestController.shared.stage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in
                switch stage {
                case .fadingIn:
                    self?.startFlashing()
                case .idle:
                    self?.stopFlashing()
                case .midRest, .fadingOut:
                    break
                }
            }
            .store(in: &cancellables)

        // 休息自然完成时给气泡提示
        RestController.shared.didFinish
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reason in
                if case .completed = reason {
                    self?.showCompletionNotification()
                }
            }
            .store(in: &cancellables)
    }

    /// 处理阶段变化
    private func handlePhaseChange(_ phase: AppPhase) {
        updateIcon()

        if case .resting = phase {
            // 进入休息状态，停止闪烁
            stopFlashing()
        }
    }

    /// 开始闪烁动画（呼吸式）
    private func startFlashing() {
        flashTimer?.invalidate()

        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem?.button else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                button.animator().alphaValue = button.alphaValue == 1.0 ? 0.3 : 1.0
            }
        }
    }

    /// 停止闪烁动画
    private func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil

        // 恢复正常透明度
        if let button = statusItem?.button {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                button.animator().alphaValue = 1.0
            }
        }
    }

    /// 显示完成休息气泡提示
    private func showCompletionNotification() {
        // NSUserNotification 已废弃，暂时不显示通知
        // TODO: 使用 UNUserNotificationCenter 替代
    }

    // MARK: - Snooze submenu

    private func createSnoozeSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let options: [(title: String, symbol: String, minutes: Int?)] = [
            (L("5 分钟"),       "5.circle",      5),
            (L("15 分钟"),      "15.circle",     15),
            (L("30 分钟"),      "30.circle",     30),
            (L("1 小时"),       "clock",         60),
            (L("至今日结束"),   "moon.circle",   nil)
        ]

        for option in options {
            let item = NSMenuItem(
                title: option.title,
                action: #selector(snoozeAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.minutes as Any
            if let image = NSImage(systemSymbolName: option.symbol, accessibilityDescription: option.title) {
                image.isTemplate = true
                item.image = image
            }
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func snoozeAction(_ sender: NSMenuItem) {
        if let minutes = sender.representedObject as? Int {
            TimerManager.shared.pause(duration: TimeInterval(minutes * 60))
        } else {
            TimerManager.shared.pause(duration: nil)
        }
    }

    // MARK: - Menu Actions

    @objc private func pause1Hour() {
        TimerManager.shared.pause(duration: 3600)
    }

    @objc private func pauseUntilEndOfDay() {
        TimerManager.shared.pause(duration: nil)
    }

    @objc private func resumeTimer() {
        TimerManager.shared.resume()
    }

    @objc private func openSettings() {
        SettingsWindowManager.shared.showSettings()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "LumenFocus",
            .credits: NSAttributedString(
                string: L("温柔的护眼提醒 — 屏幕缓慢渐暗，提醒你看向远方。所有数据仅存于本机。"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ])
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// 测试休息遮罩（立即触发）
    @objc private func triggerTestRest() {
        TimerManager.shared.triggerManualRest()
    }

    /// 重置并显示欢迎引导
    @objc private func resetAndShowOnboarding() {
        // 重置引导状态
        AppSettings.shared.hasCompletedOnboarding = false
        // 显示引导窗口（允许关闭）
        OnboardingWindowManager.shared.showOnboarding(allowClose: true) {
            // 引导完成后的回调（这里不需要额外操作）
        }
    }
}

// MARK: - NSMenuDelegate

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // 右键菜单每次都在 showContextMenu 中重新构造，无需在此刷新
    }
}
