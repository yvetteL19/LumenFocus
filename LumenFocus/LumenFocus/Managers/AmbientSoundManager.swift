//
//  AmbientSoundManager.swift
//  LumenFocus
//
//  Plays a looping ambient track during rest. Three royalty-free options:
//  rain, white noise, forest. Files expected at
//  Resources/Sounds/{rain,whitenoise,forest}.m4a (bundle root).
//
//  Gracefully no-ops if audio files are missing so the app still ships
//  before the sound assets are added.
//

import Foundation
import AVFoundation

/// 休息时可选的环境音轨
enum AmbientTrack: String, CaseIterable, Identifiable, Codable {
    case off
    case rain
    case whiteNoise
    case forest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:        return L("关闭")
        case .rain:       return L("轻雨")
        case .whiteNoise: return L("白噪音")
        case .forest:     return L("森林")
        }
    }

    var resourceName: String? {
        switch self {
        case .off:        return nil
        case .rain:       return "rain"
        case .whiteNoise: return "whitenoise"
        case .forest:     return "forest"
        }
    }
}

final class AmbientSoundManager {
    static let shared = AmbientSoundManager()

    private var player: AVAudioPlayer?
    private(set) var currentTrack: AmbientTrack = .off

    private init() {}

    /// 播放指定音轨。若已在播放同一音轨则忽略；若资源缺失则记日志后无操作
    func play(_ track: AmbientTrack) {
        guard track != .off else {
            stop()
            return
        }
        if currentTrack == track && player?.isPlaying == true {
            return
        }

        guard let name = track.resourceName,
              let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            Log.system.warning("Ambient sound asset missing for \(track.rawValue, privacy: .public); skipping playback")
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1   // 无限循环
            p.volume = 0
            p.prepareToPlay()
            p.play()
            // 1 秒淡入
            p.setVolume(0.6, fadeDuration: 1.0)
            player = p
            currentTrack = track
        } catch {
            Log.system.error("AmbientSoundManager play error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 停止播放（带 0.5s 淡出）
    func stop() {
        guard let p = player else {
            currentTrack = .off
            return
        }
        p.setVolume(0, fadeDuration: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            p.stop()
            self?.player = nil
            self?.currentTrack = .off
        }
    }
}
