//
//  MenuBarPopoverView.swift
//  LumenFocus
//
//  Popover content shown on left-click of the menu-bar icon.
//  Today summary + streak + current-cycle ring + action shortcuts.
//

import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var appState = AppState.shared

    /// 关闭 popover 的回调（由宿主 NSPopover 注入）
    var onClose: () -> Void = {}

    @State private var streak: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            ringSection
            Divider()
            actionsSection
        }
        .padding(20)
        .frame(width: 300)
        .background(Color.LumenFocus.backgroundPrimary)
        .onAppear { refresh() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日护眼")
                    .font(.system(size: 12))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                Text(verbatim: String(format: L("%d 次 · %@"), appState.todayRestCount, appState.formattedTodayWorkDuration))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.LumenFocus.textPrimary)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                    Text(verbatim: String(format: L("%d 天"), streak))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Color.LumenFocus.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.LumenFocus.backgroundSecondary)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Ring / Progress

    private var ringSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.LumenFocus.gray400.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: appState.progress)
                    .stroke(Color.LumenFocus.ink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: appState.progress)
                Text(appState.formattedRemainingTime)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.LumenFocus.textPrimary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: phaseLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.LumenFocus.textPrimary)
                Text(verbatim: phaseDetail)
                    .font(.system(size: 11))
                    .foregroundColor(Color.LumenFocus.textSecondary)
            }
            Spacer()
        }
    }

    private var phaseLabel: String {
        switch appState.currentPhase {
        case .working:        return L("工作中")
        case .triggeringRest: return L("渐暗中…")
        case .resting:        return L("休息中")
        case .paused:         return L("已暂停")
        case .autoSuspended:  return L("已自动暂停")
        }
    }

    private var phaseDetail: String {
        switch appState.currentPhase {
        case .working:        return String(format: L("下次休息在 %d 分钟后"), appState.remainingSeconds / 60)
        case .triggeringRest, .resting: return String(format: L("再过 %@ 回到工作"), appState.formattedRemainingTime)
        case .paused:         return L("通过菜单恢复")
        case .autoSuspended(let r): return autoSuspendDetail(r)
        }
    }

    private func autoSuspendDetail(_ reason: AutoSuspendReason) -> String {
        switch reason {
        case .idle:        return L("检测到无操作")
        case .videoCall:   return L("检测到视频通话")
        case .fullscreen:  return L("检测到全屏应用")
        case .focusMode:   return L("系统勿扰模式")
        case .screenLocked:return L("屏幕已锁定")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            phaseControls
            Divider().padding(.vertical, 4)
            PopoverActionRow(systemName: "chart.bar.xaxis", label: "详细统计") {
                onClose()
                StatisticsWindowManager.shared.show()
            }
            PopoverActionRow(systemName: "gearshape", label: "设置…", shortcut: "⌘,") {
                onClose()
                SettingsWindowManager.shared.showSettings()
            }
            PopoverActionRow(systemName: "xmark.circle", label: "退出 LumenFocus", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// 随当前阶段变化的主控制项（全部在左键 popover 内，无需右键）
    @ViewBuilder private var phaseControls: some View {
        switch appState.currentPhase {
        case .working:
            PopoverActionRow(systemName: "moon.circle", label: "现在休息") {
                onClose()
                TimerManager.shared.triggerManualRest()
            }
            snoozeMenu
        case .paused, .autoSuspended:
            PopoverActionRow(systemName: "play.circle", label: "恢复护眼") {
                onClose()
                TimerManager.shared.resume()
            }
        case .triggeringRest, .resting:
            PopoverActionRow(systemName: "stop.circle", label: "提前结束休息") {
                onClose()
                RestController.shared.cancelRest()
            }
        }
    }

    /// 「稍后提醒」下拉，避免一长串选项铺满 popover
    private var snoozeMenu: some View {
        Menu {
            Button(action: { snooze(5) })  { Text("5 分钟") }
            Button(action: { snooze(15) }) { Text("15 分钟") }
            Button(action: { snooze(30) }) { Text("30 分钟") }
            Button(action: { snooze(60) }) { Text("1 小时") }
            Button(action: { snoozeUntilEndOfDay() }) { Text("至今日结束") }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge")
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text("稍后提醒")
                    .font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(Color.LumenFocus.textTertiary)
            }
            .foregroundColor(Color.LumenFocus.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func snooze(_ minutes: Int) {
        onClose()
        TimerManager.shared.pause(duration: TimeInterval(minutes * 60))
    }

    private func snoozeUntilEndOfDay() {
        onClose()
        TimerManager.shared.pause(duration: nil)
    }

    // MARK: - Refresh

    private func refresh() {
        streak = StatisticsManager.shared.getCurrentStreak()
    }
}

private struct PopoverActionRow: View {
    let systemName: String
    let label: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(verbatim: L(label))
                    .font(.system(size: 13))
                Spacer()
                if let s = shortcut {
                    Text(s)
                        .font(.system(size: 11))
                        .foregroundColor(Color.LumenFocus.textTertiary)
                }
            }
            .foregroundColor(Color.LumenFocus.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(hovering ? Color.LumenFocus.backgroundSecondary : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
