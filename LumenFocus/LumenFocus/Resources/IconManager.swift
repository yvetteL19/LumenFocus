//
//  IconManager.swift
//  LumenFocus
//
//  Created by AI Director on 2026/2/4.
//  Design Spec: Based on design_spec.md section 2
//

import AppKit

/// 菜单栏图标管理器 - 生成3级进度图标
class IconManager {
    static let shared = IconManager()

    private init() {}

    // MARK: - Icon Generation

    /// 生成满格图标（100%-67%）
    func fullIcon() -> NSImage {
        return createProgressIcon(filledBars: 3, color: .labelColor)
    }

    /// 生成半格图标（66%-34%）
    func halfIcon() -> NSImage {
        return createProgressIcon(filledBars: 2, color: .labelColor)
    }

    /// 生成低电图标（33%-1%）- 黑白极简风格统一使用灰色
    func lowIcon() -> NSImage {
        return createProgressIcon(filledBars: 1, color: .lumenfocus.gray600)
    }

    /// 生成勿扰图标
    func pausedIcon() -> NSImage {
        // 使用SF Symbol
        if let pauseImage = NSImage(systemSymbolName: "zzz", accessibilityDescription: "Paused") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            return pauseImage.withSymbolConfiguration(config) ?? pauseImage
        }

        // 备用：文字图标
        return createTextIcon(text: "😴", color: .systemGray)
    }

    // MARK: - Private Methods

    /// 创建进度条图标
    /// - Parameters:
    ///   - filledBars: 填充的格子数（1-3）
    ///   - color: 图标颜色
    private func createProgressIcon(filledBars: Int, color: NSColor) -> NSImage {
        let size = NSSize(width: 22, height: 22)

        // 使用 NSImage 的 block-based drawing API，线程安全
        let image = NSImage(size: size, flipped: false) { rect in
            // 绘制眼睛符号（使用SF Symbol）
            if let eyeSymbol = NSImage(systemSymbolName: "eye", accessibilityDescription: "Eye") {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                let configuredEye = eyeSymbol.withSymbolConfiguration(config) ?? eyeSymbol

                // 绘制眼睛图标
                let eyeRect = NSRect(x: 2, y: 6, width: 12, height: 12)
                configuredEye.draw(in: eyeRect)
            }

            // 绘制进度条（3个小格子）
            let barWidth: CGFloat = 2.5
            let barHeight: CGFloat = 8
            let barSpacing: CGFloat = 1.5
            let startX: CGFloat = 14

            for i in 0..<3 {
                let barX = startX + CGFloat(i) * (barWidth + barSpacing)
                let barY: CGFloat = 7

                let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)

                if i < filledBars {
                    // 填充格
                    color.setFill()
                } else {
                    // 空格（半透明）
                    color.withAlphaComponent(0.2).setFill()
                }

                let path = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
                path.fill()
            }

            return true
        }

        // 设置为template image以支持浅色/深色模式
        image.isTemplate = true
        return image
    }

    /// 创建文字图标（备用方案）
    private func createTextIcon(text: String, color: NSColor) -> NSImage {
        let font = NSFont.systemFont(ofSize: 16, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let size = text.size(withAttributes: attributes)

        // 使用 NSImage 的 block-based drawing API，线程安全
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: .zero, withAttributes: attributes)
            return true
        }

        return image
    }

    /// 根据进度百分比获取图标
    /// - Parameter progress: 进度（0.0-1.0）
    /// - Returns: 对应的图标
    func iconForProgress(_ progress: Double) -> NSImage {
        if progress > 0.67 {
            return fullIcon()
        } else if progress > 0.34 {
            return halfIcon()
        } else {
            return lowIcon()
        }
    }
}
