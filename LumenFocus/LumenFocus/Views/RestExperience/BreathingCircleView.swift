//
//  BreathingCircleView.swift
//  LumenFocus
//
//  4-7-8 breathing pattern visualised. White circle scales 1.0 → 1.4 → 1.0
//  guided by inhale (4s) → hold (7s) → exhale (8s) cycle.
//

import SwiftUI

/// 呼吸节律视图（黑白极简，嵌入休息蒙层中段）
struct BreathingCircleView: View {
    /// 呼吸阶段
    private enum Phase: Equatable {
        case inhale     // 4s
        case hold       // 7s
        case exhale     // 8s

        var duration: Double {
            switch self {
            case .inhale: return 4
            case .hold:   return 7
            case .exhale: return 8
            }
        }

        var label: String {
            switch self {
            case .inhale: return "吸气"
            case .hold:   return "屏息"
            case .exhale: return "呼气"
            }
        }

        var next: Phase {
            switch self {
            case .inhale: return .hold
            case .hold:   return .exhale
            case .exhale: return .inhale
            }
        }

        /// 圆环的目标缩放比例
        var targetScale: CGFloat {
            switch self {
            case .inhale: return 1.4
            case .hold:   return 1.4
            case .exhale: return 1.0
            }
        }
    }

    @State private var phase: Phase = .inhale
    @State private var scale: CGFloat = 1.0
    @State private var nextPhaseTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 220, height: 220)

                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 160, height: 160)
                    .scaleEffect(scale)
                    .animation(.easeInOut(duration: phase.duration), value: scale)
            }

            Text(verbatim: L(phase.label))
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white.opacity(0.85))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: phase)
        }
        .onAppear { startCycle() }
        .onDisappear { nextPhaseTask?.cancel() }
    }

    private func startCycle() {
        runPhase(.inhale)
    }

    private func runPhase(_ p: Phase) {
        phase = p
        scale = p.targetScale

        nextPhaseTask?.cancel()
        nextPhaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(p.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            runPhase(p.next)
        }
    }
}

#Preview {
    BreathingCircleView()
        .frame(width: 400, height: 400)
        .background(Color.black)
}
