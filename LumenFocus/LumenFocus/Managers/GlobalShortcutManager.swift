//
//  GlobalShortcutManager.swift
//  LumenFocus
//
//  Registers ⌘⌥E as a global shortcut that triggers an immediate rest.
//  Uses Carbon's RegisterEventHotKey — sandbox-safe, no entitlement required.
//

import AppKit
import Carbon.HIToolbox

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// 4-char codes 用于唯一标识此快捷键
    private static let signature: OSType = {
        // "LFcS" — LumenFocus Carbon Shortcut
        return OSType(("L" as Character).asciiValue!) << 24
             | OSType(("F" as Character).asciiValue!) << 16
             | OSType(("c" as Character).asciiValue!) << 8
             | OSType(("S" as Character).asciiValue!)
    }()
    private static let hotKeyID: UInt32 = 1

    private init() {}

    /// 注册立即休息快捷键
    func registerImmediateRest() {
        unregister()

        let keyCode = UInt32(kVK_ANSI_E)
        let modifiers = UInt32(cmdKey | optionKey)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    Log.system.info("Global shortcut ⌘⌥E fired")
                    TimerManager.shared.toggleRestViaShortcut()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installStatus == noErr else {
            Log.system.error("InstallEventHandler failed: \(installStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            Log.system.error("RegisterEventHotKey failed: \(status)")
            return
        }
        Log.system.info("Global shortcut ⌘⌥E registered")
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }
}
