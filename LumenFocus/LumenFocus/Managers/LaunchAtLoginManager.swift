//
//  LaunchAtLoginManager.swift
//  LumenFocus
//
//  Manages launch at login via SMAppService (macOS 13+).
//

import Foundation
import ServiceManagement

/// 开机自启动管理器
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    /// 启用开机自启动
    @discardableResult
    func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            Log.system.error("启用开机自启失败: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 禁用开机自启动
    @discardableResult
    func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            Log.system.error("禁用开机自启失败: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 当前是否已启用
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
