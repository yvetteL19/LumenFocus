import Cocoa
import Combine
import SwiftUI

/// Both menu-bar entry points expose the same reminder semantics.
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private let appState = AppState.shared
    private let settings = AppSettings.shared

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(onClose: { [weak self] in self?.popover?.performClose(nil) }))
        self.popover = popover
        appState.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &cancellables)
        settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .lumenFocusOnboardingCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.showPopover() }
            .store(in: &cancellables)
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        switch appState.currentPhase {
        case .paused, .autoSuspended:
            button.image = IconManager.shared.pausedIcon()
        case .reminderDue:
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: L("休息提醒"))
            button.image?.isTemplate = true
        default:
            button.image = IconManager.shared.progressIcon(appState.progress)
        }
        button.alphaValue = 1
        button.imagePosition = .imageLeading
        button.title = settings.showRemainingMinutesInMenuBar && appState.isWorking
            ? " \(ReminderPresentation.menuBarCountdown(seconds: appState.remainingSeconds))" : ""
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    private var tooltip: String {
        switch appState.currentPhase {
        case .working:
            if let detail = appState.environmentDetail, !detail.isEmpty { return "LumenFocus · " + detail }
            return appState.nextReminderDate.map { String(format: L("LumenFocus · 下次提醒 %@"), reminderClockText($0)) } ?? "LumenFocus"
        case .reminderDue: return L("LumenFocus · 休息提醒待处理")
        case .triggeringRest, .resting: return String(format: L("LumenFocus · 剩余休息 %@"), appState.formattedRemainingTime)
        case .paused(let until):
            switch until {
            case .duration(let date): return String(format: L("暂停至 %@"), reminderClockText(date))
            case .endOfDay: return L("已暂停至今日结束")
            }
        case .autoSuspended: return appState.environmentDetail ?? L("提醒暂缓")
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else if popover?.isShown == true { popover?.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func item(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let header = item(tooltip, action: nil)
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        switch appState.currentPhase {
        case .working, .reminderDue:
            menu.addItem(item(L("现在休息"), action: #selector(startRest)))
            let delay = item(L("延后本次"), action: nil)
            let submenu = NSMenu()
            for minutes in [2, 5, 10] {
                let base = appState.currentPhase == .reminderDue ? Date() : (appState.nextReminderDate ?? Date())
                let title = String(format: L("延后 %d 分钟 · %@"), minutes, reminderClockText(base.addingTimeInterval(TimeInterval(minutes * 60))))
                let entry = item(title, action: #selector(delayReminder(_:)))
                entry.tag = minutes
                submenu.addItem(entry)
            }
            delay.submenu = submenu
            menu.addItem(delay)
            if appState.currentPhase == .reminderDue { menu.addItem(item(L("跳过本次"), action: #selector(skipReminder))) }
            addPauseMenu(to: menu)
        case .paused:
            menu.addItem(item(L("恢复提醒"), action: #selector(resume)))
            menu.addItem(item(L("休息并恢复提醒"), action: #selector(startRest)))
            addPauseMenu(to: menu, title: L("调整暂停时间"))
        case .autoSuspended:
            menu.addItem(item(L("现在休息"), action: #selector(startRest)))
            addPauseMenu(to: menu)
        case .triggeringRest, .resting:
            menu.addItem(item(L("结束休息"), action: #selector(endRest)))
            menu.addItem(item(L("2 分钟后再提醒"), action: #selector(postponeRest)))
        }
        menu.addItem(.separator())
        menu.addItem(item(L("详细统计"), action: #selector(openStatistics)))
        menu.addItem(item(L("设置…"), action: #selector(openSettings), key: ","))
        menu.addItem(item(L("重新体验引导"), action: #selector(showOnboarding)))
        menu.addItem(.separator())
        menu.addItem(item(L("退出 LumenFocus"), action: #selector(quit), key: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func addPauseMenu(to menu: NSMenu, title: String = L("暂停提醒")) {
        let pause = item(title, action: nil)
        let submenu = NSMenu()
        for minutes in [15, 60] {
            let title = ReminderPresentation.pauseOptionTitle(minutes: minutes)
            let entry = item(title, action: #selector(pauseFor(_:)))
            entry.tag = minutes
            submenu.addItem(entry)
        }
        submenu.addItem(item(L("至今日结束"), action: #selector(pauseToday)))
        pause.submenu = submenu
        menu.addItem(pause)
    }

    @objc private func startRest() { TimerManager.shared.triggerManualRest() }
    @objc private func endRest() { RestController.shared.cancelRest() }
    @objc private func postponeRest() { RestController.shared.snooze(by: 120) }
    @objc private func delayReminder(_ sender: NSMenuItem) { TimerManager.shared.snoozeReminder(by: TimeInterval(sender.tag * 60)) }
    @objc private func skipReminder() { TimerManager.shared.skipReminder() }
    @objc private func pauseFor(_ sender: NSMenuItem) { TimerManager.shared.pause(duration: TimeInterval(sender.tag * 60)) }
    @objc private func pauseToday() { TimerManager.shared.pause(duration: nil) }
    @objc private func resume() { TimerManager.shared.resume() }
    @objc private func openStatistics() { StatisticsWindowManager.shared.show() }
    @objc private func openSettings() { SettingsWindowManager.shared.showSettings() }
    @objc private func showOnboarding() { OnboardingWindowManager.shared.showOnboarding(completion: {}) }
    @objc private func quit() { NSApp.terminate(nil) }
}
