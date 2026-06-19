//
//  DiagnosticsManager.swift
//  LumenFocus
//
//  Subscribes to MetricKit and persists crash / hang payloads to a local file
//  the user can export from Settings → Help. No third-party uploads.
//

import Foundation
import MetricKit

/// 本地诊断数据管理器
final class DiagnosticsManager: NSObject {
    static let shared = DiagnosticsManager()

    private let queue = DispatchQueue(label: "Yvette.LumenFocus.diagnostics", qos: .utility)
    private let fileManager = FileManager.default

    /// 诊断日志写入位置：~/Library/Application Support/LumenFocus/diagnostics/
    private lazy var directoryURL: URL? = {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport
            .appendingPathComponent("LumenFocus", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            Log.system.error("Failed to create diagnostics dir: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    private override init() {
        super.init()
    }

    /// 在 app 启动时调用一次
    func register() {
        MXMetricManager.shared.add(self)
        Log.system.info("DiagnosticsManager registered with MXMetricManager")
    }

    /// 列出已收集的诊断文件，供「导出诊断日志」按钮使用
    func collectedReports() -> [URL] {
        guard let dir = directoryURL else { return [] }
        return (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }

    /// 删除全部本地诊断数据
    func clearAll() {
        guard let dir = directoryURL else { return }
        try? fileManager.removeItem(at: dir)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func write(payload: Data, filename: String) {
        queue.async { [weak self] in
            guard let self, let dir = self.directoryURL else { return }
            let url = dir.appendingPathComponent(filename)
            do {
                try payload.write(to: url, options: .atomic)
                Log.system.info("Wrote diagnostic payload: \(filename, privacy: .public)")
            } catch {
                Log.system.error("Failed to write diagnostic \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func timestampedFilename(prefix: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(prefix)-\(formatter.string(from: Date())).json"
    }
}

// MARK: - MXMetricManagerSubscriber

extension DiagnosticsManager: MXMetricManagerSubscriber {
    // 注：macOS 上 MetricKit 仅提供 MXDiagnosticPayload（崩溃、卡顿、CPU 飙升）。
    // MXMetricPayload 是 iOS only。
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            write(payload: payload.jsonRepresentation(), filename: timestampedFilename(prefix: "diagnostic"))
        }
    }
}
