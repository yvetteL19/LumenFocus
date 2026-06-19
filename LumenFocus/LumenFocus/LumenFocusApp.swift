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
    }
}
