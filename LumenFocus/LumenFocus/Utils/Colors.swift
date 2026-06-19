//
//  Colors.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//  Design Spec: Based on design_spec.md section 1.1
//  Updated: 2026/2/5 - Black & White Minimalist Edition
//

import AppKit
import SwiftUI

// MARK: - SwiftUI Color Extensions (推荐在SwiftUI中使用)

extension Color {
    /// LumenFocus SwiftUI 颜色
    struct LumenFocus {
        // Pure Black & White
        static let black = Color(red: 0, green: 0, blue: 0)
        static let white = Color(red: 1, green: 1, blue: 1)

        // Gray Scale
        static let gray900 = Color(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0)
        static let gray800 = Color(red: 0x33/255.0, green: 0x33/255.0, blue: 0x33/255.0)
        static let gray700 = Color(red: 0x4D/255.0, green: 0x4D/255.0, blue: 0x4D/255.0)
        static let gray600 = Color(red: 0x66/255.0, green: 0x66/255.0, blue: 0x66/255.0)
        static let gray500 = Color(red: 0x80/255.0, green: 0x80/255.0, blue: 0x80/255.0)
        static let gray400 = Color(red: 0x99/255.0, green: 0x99/255.0, blue: 0x99/255.0)
        static let gray300 = Color(red: 0xCC/255.0, green: 0xCC/255.0, blue: 0xCC/255.0)
        static let gray200 = Color(red: 0xE5/255.0, green: 0xE5/255.0, blue: 0xE5/255.0)
        static let gray100 = Color(red: 0xF5/255.0, green: 0xF5/255.0, blue: 0xF5/255.0)

        // MARK: - Semantic Colors (dynamic — adapt to Light/Dark Mode)
        //
        // These map to AppKit system colors so the whole app respects the
        // user's appearance. The pure `black`/`white` above remain fixed and
        // are reserved for the always-black rest overlay and the content
        // drawn on top of it.

        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        static let textDisabled = Color(nsColor: .quaternaryLabelColor)
        static let backgroundPrimary = Color(nsColor: .windowBackgroundColor)
        static let backgroundSecondary = Color(nsColor: .controlBackgroundColor)
        static let backgroundTertiary = Color(nsColor: .underPageBackgroundColor)
        static let border = Color(nsColor: .separatorColor)
        static let borderLight = Color(nsColor: .separatorColor)
        static let separator = Color(nsColor: .separatorColor)

        /// Monochrome brand "ink" — black in Light Mode, white in Dark Mode.
        /// Use for primary fills, selected states, charts, progress rings.
        static let ink = Color(nsColor: .labelColor)
        /// The contrast color to draw on top of `ink` (white in Light, black in Dark).
        static let onInk = Color(nsColor: .lumenInkInverse)
    }
}

// MARK: - NSColor Extensions (用于AppKit组件)

extension NSColor {
    /// LumenFocus 品牌颜色
    static let lumenfocus = LumenFocusColors()

    /// 与 `labelColor` 互补的"墨色反相"：浅色模式为白、深色模式为黑。
    /// 用于绘制在纯黑/纯白主色按钮之上的文字。
    static let lumenInkInverse: NSColor = NSColor(name: "lumenInkInverse") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? .black : .white
    }

    /// 从十六进制字符串创建颜色
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: - LumenFocus NSColor System (用于AppKit)
// 使用计算属性而非静态存储属性，避免内存管理问题

struct LumenFocusColors {
    // MARK: - Pure Black & White

    /// 纯黑 #000000
    var black: NSColor { NSColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// 纯白 #FFFFFF
    var white: NSColor { NSColor(red: 1, green: 1, blue: 1, alpha: 1) }

    // MARK: - Gray Scale (10 levels)

    /// 最深灰 #1A1A1A (接近黑)
    var gray900: NSColor { NSColor(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0, alpha: 1) }

    /// 深灰 #333333
    var gray800: NSColor { NSColor(red: 0x33/255.0, green: 0x33/255.0, blue: 0x33/255.0, alpha: 1) }

    /// 中深灰 #4D4D4D
    var gray700: NSColor { NSColor(red: 0x4D/255.0, green: 0x4D/255.0, blue: 0x4D/255.0, alpha: 1) }

    /// 标准灰 #666666
    var gray600: NSColor { NSColor(red: 0x66/255.0, green: 0x66/255.0, blue: 0x66/255.0, alpha: 1) }

    /// 中性灰 #808080
    var gray500: NSColor { NSColor(red: 0x80/255.0, green: 0x80/255.0, blue: 0x80/255.0, alpha: 1) }

    /// 中浅灰 #999999
    var gray400: NSColor { NSColor(red: 0x99/255.0, green: 0x99/255.0, blue: 0x99/255.0, alpha: 1) }

    /// 浅灰 #CCCCCC
    var gray300: NSColor { NSColor(red: 0xCC/255.0, green: 0xCC/255.0, blue: 0xCC/255.0, alpha: 1) }

    /// 极浅灰 #E5E5E5
    var gray200: NSColor { NSColor(red: 0xE5/255.0, green: 0xE5/255.0, blue: 0xE5/255.0, alpha: 1) }

    /// 最浅灰 #F5F5F5 (接近白)
    var gray100: NSColor { NSColor(red: 0xF5/255.0, green: 0xF5/255.0, blue: 0xF5/255.0, alpha: 1) }

    // MARK: - Semantic Colors (dynamic — adapt to Light/Dark Mode)
    //
    // Mapped to AppKit system colors so AppKit-drawn chrome (menu-bar menu
    // views, attributed strings) respects the user's appearance. The fixed
    // black/white/gray scale above is reserved for the always-black overlay.

    /// 主要文本颜色
    var textPrimary: NSColor { .labelColor }

    /// 次要文本颜色
    var textSecondary: NSColor { .secondaryLabelColor }

    /// 三级文本颜色
    var textTertiary: NSColor { .tertiaryLabelColor }

    /// 禁用文本颜色
    var textDisabled: NSColor { .quaternaryLabelColor }

    /// 主背景颜色
    var backgroundPrimary: NSColor { .windowBackgroundColor }

    /// 次背景颜色（卡片 / 信息块）
    var backgroundSecondary: NSColor { .controlBackgroundColor }

    /// 三级背景颜色
    var backgroundTertiary: NSColor { .underPageBackgroundColor }

    /// 边框颜色
    var border: NSColor { .separatorColor }

    /// 浅边框颜色
    var borderLight: NSColor { .separatorColor }

    /// 分割线颜色
    var separator: NSColor { .separatorColor }

    /// 单色品牌墨色（浅色=黑、深色=白）
    var ink: NSColor { .labelColor }

    // MARK: - Overlay Colors

    /// 休息遮罩专用（黑色70%透明度）
    var overlayDark: NSColor { NSColor.black.withAlphaComponent(0.7) }
}
