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
        case paused, due, progress(Double)
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
        case .reminderDue: icon = .due
        default: icon = .progress(appState.progress)
        }
        if renderedIcon != icon {
            switch icon {
            case .paused: button.image = IconManager.shared.pausedIcon()
            case .due:
                button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: L("休息提醒"))
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
        case .working:
            if let detail = appState.environmentDetail, !detail.isEmpty { return "LumenFocus · " + detail }
            return appState.nextReminderDate.map { String(format: L("LumenFocus · 下次提醒 %@"), reminderClockText($0)) } ?? "LumenFocus"
        case .reminderDue: return L("LumenFocus · 可以开始休息了")
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
        if appState.currentPhase == .reminderDue {
            let duration = item(ReminderPresentation.restInvitationTitle(seconds: settings.restDurationSeconds), action: nil)
            duration.isEnabled = false
            menu.addItem(duration)
            let effect = item(L("开始后，所有屏幕会渐暗。你可以随时提前结束。"), action: nil)
            effect.isEnabled = false
            menu.addItem(effect)
        }
        menu.addItem(.separator())
        switch appState.currentPhase {
        case .working, .reminderDue:
            menu.addItem(item(presentation.primaryTitle(), action: #selector(startRest)))
            let delay = item(L(appState.currentPhase == .reminderDue ? "稍后再提醒" : "延后本次"), action: nil)
            let submenu = NSMenu()
            for minutes in ReminderPresentation.delayChoices {
                let title = presentation.delayOptionTitle(minutes: minutes)
                let entry = item(title, action: #selector(delayReminder(_:)))
                entry.tag = minutes
                submenu.addItem(entry)
            }
            delay.submenu = submenu
            menu.addItem(delay)
            if appState.currentPhase == .reminderDue {
                menu.addItem(item(ReminderPresentation.skipTitle(workMinutes: settings.workDurationMinutes), action: #selector(skipReminder)))
            }
            addPauseMenu(to: menu)
        case .paused:
            menu.addItem(item(L("恢复提醒"), action: #selector(resume)))
            menu.addItem(item(L("休息并恢复提醒"), action: #selector(startRest)))
            addPauseMenu(to: menu, title: L("调整暂停时间"))
        case .autoSuspended:
            menu.addItem(item(presentation.primaryTitle(), action: #selector(startRest)))
            addPauseMenu(to: menu)
        case .triggeringRest, .resting:
            menu.addItem(item(L("提前结束"), action: #selector(endRest)))
            menu.addItem(item(ReminderPresentation.defaultSnoozeTitle(), action: #selector(postponeRest)))
        }
        menu.addItem(.separator())
        menu.addItem(item(L("详细统计"), action: #selector(openStatistics)))
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
        submenu.addItem(item(L("至今日结束"), action: #selector(pauseToday)))
        pause.submenu = submenu
        menu.addItem(pause)
    }

    @objc private func startRest() { TimerManager.shared.triggerManualRest() }
    @objc private func endRest() { RestController.shared.cancelRest() }
    @objc private func postponeRest() { RestController.shared.snooze(by: ReminderPresentation.defaultSnoozeSeconds) }
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
