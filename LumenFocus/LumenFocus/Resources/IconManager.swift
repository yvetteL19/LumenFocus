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

    /// 满/半/低三级为兼容旧调用而保留，内部统一走连续进度环。
    func fullIcon() -> NSImage { progressIcon(1.0) }
    func halfIcon() -> NSImage { progressIcon(0.5) }
    func lowIcon()  -> NSImage { progressIcon(0.2) }

    /// 连续倒计时环图标：外圈随剩余进度顺时针收缩，中心一个圆点
    /// （呼应 App 图标的「光圈 / 眼」造型）。template 图，自动适配菜单栏明暗。
    /// - Parameter progress: 剩余进度 0.0–1.0（1.0 = 满环）
    func progressIcon(_ progress: Double) -> NSImage {
        let p = max(0.0, min(1.0, progress))
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 6.4
            let lineWidth: CGFloat = 1.8

            // 轨道（淡）
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.28).setStroke()
            track.lineCapStyle = .round
            track.stroke()

            // 进度弧（实）：从正上方 12 点顺时针收缩
            if p > 0.001 {
                let start: CGFloat = 90
                let end = start - CGFloat(p) * 360
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            // 中心圆点
            let dotR: CGFloat = 1.7
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))
            NSColor.black.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 暂停 / 自动避让图标：淡轨道 + 中心两根暂停竖条。
    func pausedIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = 6.4

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.8
            NSColor.black.withAlphaComponent(0.28).setStroke()
            track.stroke()

            // 两根暂停竖条
            let barW: CGFloat = 1.6, barH: CGFloat = 5.4, gap: CGFloat = 1.8
            NSColor.black.setFill()
            for sign in [-1.0, 1.0] {
                let bx = center.x + (sign < 0 ? -gap/2 - barW : gap/2)
                let rect = NSRect(x: bx, y: center.y - barH/2, width: barW, height: barH)
                NSBezierPath(roundedRect: rect, xRadius: 0.7, yRadius: 0.7).fill()
            }
            return true
        }
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
