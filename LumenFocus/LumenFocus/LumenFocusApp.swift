//
//  LumenFocusApp.swift
//  LumenFocus
//
//  Created by 轶微 on 2026/2/4.
//  Modified by AI Director on 2026/2/4
//

import SwiftUI

@main
struct LumenFocusApp: App {
    // 使用 NSApplicationDelegateAdaptor 集成 AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 返回空的Settings场景，因为这是纯菜单栏应用
        Settings {
            EmptyView()
        }
        .commands {
            // Use the same settings window from the native app menu and popover.
            // Otherwise SwiftUI's default Command-comma opens the empty scene.
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("休息提醒") { appDelegate.showReminders() }
                    .keyboardShortcut("1", modifiers: .command)
                Button("休息记录") { appDelegate.showStatistics() }
                    .keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}
