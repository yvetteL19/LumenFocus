//
//  FarFocusDotView.swift
//  LumenFocus
//
//  Far-focus training: a small white dot shifts across screen corners every 10s.
//  Guides the eye to track distant points — the active part of the 20-20-20 rule.
//

import SwiftUI

struct FarFocusDotView: View {
    /// 切换位置的间隔
    private let shiftInterval: TimeInterval = 8

    @State private var corner: Corner = .topLeft
    @State private var shiftTask: Task<Void, Never>?

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, center
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 20) {
                Spacer()
                Text("看向移动的亮点")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
                Text("让眼球转动是放松眼肌的关键")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .white.opacity(0.55), radius: 8)
                    .position(position(for: corner, in: geo.size))
                    .animation(.easeInOut(duration: 1.2), value: corner)
            )
        }
        .onAppear { startCycle() }
        .onDisappear { shiftTask?.cancel() }
    }

    private func position(for corner: Corner, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 60
        switch corner {
        case .topLeft:     return CGPoint(x: inset, y: inset)
        case .topRight:    return CGPoint(x: size.width - inset, y: inset)
        case .bottomLeft:  return CGPoint(x: inset, y: size.height - inset)
        case .bottomRight: return CGPoint(x: size.width - inset, y: size.height - inset)
        case .center:      return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    private func startCycle() {
        shiftTask?.cancel()
        shiftTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(shiftInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                let candidates = Corner.allCases.filter { $0 != corner }
                corner = candidates.randomElement() ?? .center
            }
        }
    }
}

#Preview {
    FarFocusDotView()
        .frame(width: 800, height: 500)
        .background(Color.black)
}
