//
//  Logger.swift
//  LumenFocus
//
//  Centralised structured logging via os.Logger.
//

import Foundation
import os

/// 本地化字符串短名（AppKit 路径用）
/// 例：`L("退出")` → en 区显示 "Quit"，zh-Hans 区显示 "退出"
@inline(__always) func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, comment: comment)
}

/// 全局 Logger 命名空间。按模块拆 category，便于在 Console.app 中过滤。
enum Log {
    private static let subsystem: String = Bundle.main.bundleIdentifier ?? "Yvette.LumenFocus"

    /// 应用生命周期、设置、系统集成（开机自启等）
    static let system = Logger(subsystem: subsystem, category: "system")

    /// 计时与状态机
    static let timer = Logger(subsystem: subsystem, category: "timer")

    /// 休息流程编排
    static let rest = Logger(subsystem: subsystem, category: "rest")

    /// 菜单栏、Popover、窗口
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// 统计与持久化
    static let stats = Logger(subsystem: subsystem, category: "stats")

    /// 环境感知（idle / 全屏 / 视频通话 / Focus）
    static let workspace = Logger(subsystem: subsystem, category: "workspace")

    /// 通知与提醒
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
