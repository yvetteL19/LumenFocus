import Cocoa
import Combine
import SwiftUI

/// Both menu-bar entry points expose the same reminder semantics.
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private let iconRefresh = MainQueueUpdateCoalescer()
    private lazy var popoverContent = PopoverContentController { [weak self] in
        NSHostingController(rootView: MenuBarPopoverView(onClose: { [weak self] in self?.popover?.performClose(nil) }))
    }
    private enum IconState: Equatable {
        case stopped, paused, progress(Double)
    }
    private var renderedIcon: IconState?
    private let appState = AppState.shared
    private let settings = AppSettings.shared

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.alphaValue = 1
            button.imagePosition = .imageLeading
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.popover = popover
        appState.objectWillChange.sink { [weak self] _ in
            self?.scheduleIconRefresh()
        }.store(in: &cancellables)
        settings.objectWillChange.sink { [weak self] _ in
            self?.scheduleIconRefresh()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .lumenFocusOnboardingCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.showPopover() }
            .store(in: &cancellables)
        updateIcon()
    }

    private func scheduleIconRefresh() {
        // Both models publish on the main thread, before their property is set.
        // Rendering once on the following turn observes the complete projection.
        iconRefresh.schedule { [weak self] in self?.updateIcon() }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let icon: IconState
        switch appState.currentPhase {
        case .paused, .autoSuspended: icon = .paused
        case .stopped: icon = .stopped
        default: icon = .progress(appState.progress)
        }
        if renderedIcon != icon {
            switch icon {
            case .paused: button.image = IconManager.shared.pausedIcon()
            case .stopped:
                button.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: L("提醒已停止"))
                button.image?.isTemplate = true
            case .progress(let progress): button.image = IconManager.shared.progressIcon(progress)
            }
            renderedIcon = icon
        }
        let title = settings.showRemainingMinutesInMenuBar && appState.isWorking
            ? " \(ReminderPresentation.menuBarCountdown(seconds: appState.remainingSeconds))" : ""
        if button.title != title { button.title = title }
        let description = tooltip
        if button.toolTip != description {
            button.toolTip = description
            button.setAccessibilityLabel(description)
        }
    }

    private var tooltip: String {
        switch appState.currentPhase {
        case .stopped: return "LumenFocus · " + L("提醒已停止")
        case .working:
            return appState.nextReminderDate.map { String(format: L("LumenFocus · 下次提醒 %@"), reminderClockText($0)) } ?? "LumenFocus"
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

    func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        popoverContent.prepare(popover)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.title = "LumenFocus"
        popover.contentViewController?.view.window?.setAccessibilityLabel("LumenFocus")
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    private func item(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func showContextMenu() {
        let presentation = ReminderPresentation(phase: appState.currentPhase, remainingSeconds: appState.remainingSeconds,
            nextReminderDate: appState.nextReminderDate, environmentDetail: appState.environmentDetail,
            restDurationSeconds: settings.restDurationSeconds, lastRestOutcome: appState.lastRestOutcome)
        let menu = NSMenu()
        let header = item(tooltip, action: nil)
        header.isEnabled = false
        menu.addItem(header)
        if let outcome = presentation.outcomeText() {
            let result = item(outcome, action: nil)
            result.isEnabled = false
            menu.addItem(result)
        }
        menu.addItem(.separator())
        switch appState.currentPhase {
        case .stopped:
            menu.addItem(item(L("开启提醒"), action: #selector(startReminders)))
        case .working:
            menu.addItem(item(presentation.primaryTitle(), action: #selector(startRest)))
            menu.addItem(item(ReminderPresentation.skipTitle(workMinutes: settings.workDurationMinutes), action: #selector(skipReminder)))
            addPauseMenu(to: menu)
        case .paused:
            menu.addItem(item(L("恢复提醒"), action: #selector(resume)))
            addPauseMenu(to: menu, title: L("调整暂停时间"))
        case .autoSuspended:
            addPauseMenu(to: menu)
        case .triggeringRest, .resting:
            menu.addItem(item(L("返回工作"), action: #selector(endRest)))
            addPauseMenu(to: menu)
        }
        if appState.currentPhase != .stopped {
            menu.addItem(item(L("停止提醒"), action: #selector(stopReminders)))
        }
        menu.addItem(.separator())
        menu.addItem(item(L("记录"), action: #selector(openStatistics)))
        menu.addItem(item(L("设置…"), action: #selector(openSettings), key: ","))
        menu.addItem(item(L("重新设置休息节奏…"), action: #selector(showOnboarding)))
        menu.addItem(.separator())
        menu.addItem(item(L("退出 LumenFocus"), action: #selector(quit), key: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func addPauseMenu(to menu: NSMenu, title: String = L("暂停提醒")) {
        let pause = item(title, action: nil)
        let submenu = NSMenu()
        for minutes in ReminderPresentation.pauseChoices {
            let title = ReminderPresentation.pauseOptionTitle(minutes: minutes)
            let entry = item(title, action: #selector(pauseFor(_:)))
            entry.tag = minutes
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item(L("自定义暂停…"), action: #selector(customPause)))
        pause.submenu = submenu
        menu.addItem(pause)
    }

    @objc private func startRest() { TimerManager.shared.triggerManualRest() }
    @objc private func endRest() { RestController.shared.cancelRest() }
    @objc private func skipReminder() { TimerManager.shared.skipReminder() }
    @objc private func pauseFor(_ sender: NSMenuItem) { TimerManager.shared.pause(duration: TimeInterval(sender.tag * 60)) }
    @objc private func customPause() { ReminderPauseWindowManager.shared.show() }
    @objc private func startReminders() { TimerManager.shared.startReminders() }
    @objc private func stopReminders() { TimerManager.shared.stopReminders() }
    @objc private func resume() { TimerManager.shared.resume() }
    @objc private func openStatistics() { StatisticsWindowManager.shared.show() }
    @objc private func openSettings() { SettingsWindowManager.shared.showSettings() }
    @objc private func showOnboarding() { OnboardingWindowManager.shared.showOnboarding(completion: {}) }
    @objc private func quit() { NSApp.terminate(nil) }
}
