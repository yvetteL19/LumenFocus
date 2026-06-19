# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LumenFocus is a macOS menu-bar app for eye-care reminders. Work/rest cycles drive a full-screen semi-transparent overlay that gradually dims the screen, encouraging the user to look away. The app runs as a menu-bar-only utility — `LSUIElement = true` in `Info.plist` hides the Dock icon, with `NSApp.setActivationPolicy(.accessory)` in `AppDelegate` as a runtime backup.

**Target:** macOS 13.0+
**Language:** Swift 5.0
**Frameworks:** SwiftUI (popover, settings, onboarding, in-overlay activities), AppKit (menu bar, overlay windows), Combine (reactive state), Charts (popover & stats), MetricKit (local crash/hang logging), Carbon HIToolbox (global hotkey)
**Bundle ID (current):** `Yvette.LumenFocus` — must be renamed to a proper reverse-domain ID before MAS submission (see `M7` in `/Users/yiwei/.claude/plans/app-atore-checklist-app-precious-sutton.md`)

UI strings are localised via `Localizable.strings` in `en.lproj/` and `zh-Hans.lproj/`. SwiftUI `Text("key")` auto-localises; AppKit code uses the `L("key")` helper in `Utils/Logger.swift`. Tip library (`Resources/Tips.swift`) is locale-aware via separate Chinese / English buckets.

## Build & Run

GUI:

```
open LumenFocus/LumenFocus.xcodeproj
```

CLI:

```
cd LumenFocus
xcodebuild -project LumenFocus.xcodeproj -scheme LumenFocus -configuration Debug -destination 'platform=macOS' build
```

Tests live in `LumenFocusTests/` but a test target must be created once in Xcode UI — see `LumenFocusTests/README.md`. After that:

```
xcodebuild -project LumenFocus.xcodeproj -scheme LumenFocus -destination 'platform=macOS' test
```

Widget Extension sources live in `LumenFocusWidget/` — see `LumenFocusWidget/README.md` for the one-time Xcode target setup (App Group `group.Yvette.LumenFocus` required).

## Architecture

### App Lifecycle
- `LumenFocusApp.swift` — SwiftUI `@main`, hands off to `AppDelegate` via `@NSApplicationDelegateAdaptor`.
- `AppDelegate.swift` — sets accessory activation policy, boots `DiagnosticsManager`, `WeeklyRecapManager`, `WorkspaceMonitor`, `GlobalShortcutManager`, then creates `MenuBarController`.

### Singleton managers (all `.shared`)
- `TimerManager` — work-period heartbeat (1s tick). Delegates the entire rest phase to `RestController`. Subscribes to `WorkspaceMonitor.pauseSignal` to auto-suspend during meetings/idle/fullscreen.
- `RestController` — **single source of truth for rest lifecycle**. Owns the `RestStage` state machine (`idle → fadingIn → midRest → fadingOut`) and the `MidRestActivity` sub-state (`breathing → farFocus → free`). Publishes via Combine. Drives `AppState.currentPhase` and `AmbientSoundManager`.
- `RestManager` — pure rendering layer. Subscribes to `RestController.stage` and creates/tears down `RestOverlayWindow` per screen. No business state.
- `WorkspaceMonitor` — environment signal aggregator (idle / fullscreen / video call / screen lock). Bundle-ID whitelist for Zoom, Teams, FaceTime, Meet, Keynote, etc. Publishes `pauseSignal: PauseSignal?` via Combine.
- `AppSettings` — user preferences in `UserDefaults`. New M1-M6 fields: `enableSmartDetection` + 4 sub-toggles, `ambientTrack`, `showRemainingMinutesInMenuBar`.
- `AppState` — runtime state with `currentPhase: AppPhase` (`.working / .triggeringRest / .resting / .paused / .autoSuspended`).
- `StatisticsManager` — daily aggregates + `getCurrentStreak()` / `getLongestStreak()` (≥4 rests = day达标).
- `WeeklyRecapManager` — schedules a Sunday 20:00 local notification with weekly summary.
- `AmbientSoundManager` — loops rain/whitenoise/forest from `Resources/Sounds/*.m4a` during rest (no-ops if assets missing).
- `MenuBarController` — `NSStatusItem` with **left-click popover** (`MenuBarPopoverView`) and **right-click NSMenu**. Icon swap + breathing animation.
- `SettingsWindowManager`, `OnboardingWindowManager`, `StatisticsWindowManager` — `NSHostingView` lazy window hosts.
- `OnboardingDemo` — 10s compressed rest demo for Onboarding step 2; isolated from production state (no `AppState`/stats side effects).
- `LaunchAtLoginManager` — `SMAppService` wrapper (macOS 13+).
- `DiagnosticsManager` — `MXMetricManager` subscriber, writes payloads to `~/Library/Application Support/LumenFocus/diagnostics/`.
- `GlobalShortcutManager` — ⌘⌥E hotkey via Carbon `RegisterEventHotKey` (sandbox-safe).
- `SharedDataAccess` (`Utils/`) — App Group bridge to the Widget extension. Falls back to standard UserDefaults when the App Group isn't configured yet.

### State machine (`Models/AppState.swift` + `Managers/RestController.swift`)

```
                  TimerManager.tick (1Hz)
                          │
working ──(time up)──► RestController.beginRest
                          │
                          ▼
                fadingIn (0~20s, via tickRest computing elapsed)
                          │
                          ▼
                  midRest ── { breathing → farFocus → free }
                          │
                          ▼
                fadingOut (last 20s)
                          │
                          ▼
                       idle ──► AppState.completeRest → working
   │
   ├──► WorkspaceMonitor.pauseSignal != nil ──► autoSuspended(reason)
   │                                              │
   │                                       (signal cleared)
   │                                              │
   │                                              ▼
   └────────────────────────────────────────► working
       (snooze 1h, snooze EOD, etc.)
                ▼
              paused(.duration / .endOfDay)
```

The 20s fade-in is **not** a `DispatchQueue.asyncAfter` — it's derived from `RestController.tickRest(elapsed:)` driven by `TimerManager.tick`. No race conditions.

### Rest-cycle Combine streams (`RestController.swift`)
- `stage: CurrentValueSubject<RestStage, Never>` — drives `RestManager` window lifecycle and `MenuBarController` icon flashing
- `midRestActivity: CurrentValueSubject<MidRestActivity, Never>` — drives main-screen `RestOverlayWindow` SwiftUI subview swap (breathing circle ↔ far-focus dot ↔ free tips)
- `didFinish: PassthroughSubject<RestEndReason, Never>` — drives `TimerManager.handleRestFinished` (rolls back to working, applies snooze offset, etc.)

### Localization

- `Utils/Logger.swift` provides `L("key")` shorthand for `NSLocalizedString`
- SwiftUI `Text("key")` auto-uses LocalizedStringKey
- `en.lproj/Localizable.strings` has full translations of all visible strings
- `zh-Hans.lproj/Localizable.strings` exists primarily so Xcode considers zh-Hans a supported region; values mostly equal keys
- `Resources/Tips.swift` switches between `morningZh/morningEn` etc. based on `Locale.current.language.languageCode`

### Multi-monitor
`RestManager` builds one `RestOverlayWindow` per `NSScreen`. Only the window whose `screen == NSScreen.main` runs `setupUIElements` and `setupMidRestHosting`, so the breathing / far-focus SwiftUI views render on the main display. `handleScreenConfigurationChange` rebuilds windows mid-rest on display hot-plug.

## Design system

Black-and-white minimalist (see `Utils/Colors.swift`).

### Colors
`Color.LumenFocus.*` (SwiftUI) and `NSColor.lumenfocus.*` (AppKit). No colored elements. Semantic tokens: `textPrimary` (#1A1A1A), `textSecondary` (#666666), `backgroundPrimary` (#FFFFFF), `backgroundSecondary` (#F5F5F5), `gray800` (#333333) for icons, `border` (#CCCCCC).

### Spacing & radius
8pt grid; standard corner radius 8pt.

### SF Symbols
All AppKit icons use `isTemplate = true`. SwiftUI uses default tint.

## Key implementation details

### Overlay window (`Views/RestOverlayWindow.swift`)
- Level `.screenSaver + 1` (above fullscreen apps)
- Collection behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
- Borderless; inner `NSView` carries the black layer, animated via `alphaValue` (target 0.7)
- `fadeIn(duration:)` / `fadeOut(duration:)` accept custom duration so `OnboardingDemo` can use 3s instead of 20s
- "再撑 2 分钟" SwiftUI-styled NSButton visible for the first 5s of fade-in, then fades out
- ESC → `RestController.shared.cancelRest()` (direct call, no notification round-trip)
- Main-screen window hosts an `NSHostingView<AnyView>` that swaps between `BreathingCircleView` (4-7-8 pattern), `FarFocusDotView` (corner-shifting dot), and the existing tip label as `RestController.midRestActivity` changes

### Timing constants (`AppSettings`)
- Work: 15–120 minutes, default 40
- Rest: 1–15 minutes, default 5
- `RestController.fadeInDuration = 20`, `fadeOutDuration = 20`
- mid-rest split: 50% breathing / 25% farFocus / 25% free

### Persistence
- `UserDefaults` for everything (no iCloud, by product decision)
- Daily keys `restCount_<yyyy-MM-dd>` + `dailyStatisticsData` JSON blob
- 30-day cleanup in `StatisticsManager.cleanupOldData()`
- `SharedDataAccess` mirrors a today-snapshot to the App Group for Widget consumption
- `LumenFocus.xcdatamodeld` is unused scaffold — do not add Core Data

### Logging
- `os.Logger` via `Log.system`, `Log.timer`, `Log.rest`, `Log.ui`, `Log.stats`, `Log.workspace`, `Log.notifications`
- No `print` calls. Filter `Console.app` by subsystem `Yvette.LumenFocus`

### Sandbox entitlements
- `app-sandbox`, `files.user-selected.read-only`, `files.user-selected.read-write`
- Widget setup adds `application-groups` → `group.Yvette.LumenFocus`

## Plan & roadmap

The full商业化 roadmap is at `/Users/yiwei/.claude/plans/app-atore-checklist-app-precious-sutton.md`. M0–M6 is implemented. **M7 (App Store compliance checklist) is intentionally deferred** per user direction — see the plan for the full pre-submission gate list.
