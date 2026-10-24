# LumenFocus development guide

LumenFocus is a local macOS menu-bar break reminder for a user who loses track of time while deeply focused. Its only reminder flow silently dims all displays automatically. Any key, including Escape, immediately returns to work; otherwise the overlay brightens away when the break timer ends. It never pauses or controls underlying apps. The current product authority is `docs/product-contract.md` (2026-10-24); older gentle-reminder and app-avoidance decisions are superseded.

## Platform and commands

- macOS 13+, Swift 5, SwiftUI, AppKit, Combine; no third-party runtime dependencies.
- Main bundle: `Yvette.LumenFocus`. Preserve this identity for existing installs; any distribution change requires a separate migration decision.
- Open `LumenFocus/LumenFocus.xcodeproj`. The shared `LumenFocus` scheme includes the hosted `LumenFocusTests` target.
- Test from the repository root:

```sh
xcodebuild -project LumenFocus/LumenFocus.xcodeproj -scheme LumenFocus \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

- GitHub Actions tests Debug, validates release-check failure fixtures and source metadata, and archives/packages a universal unsigned Release for internal testing. First release targets the Mac App Store; Apple Developer membership, distribution signing, TestFlight and App Review remain separate gates. See `docs/app-store-readiness.md` and `docs/release-build.md`.
- Widget sources are not integrated into a target. Do not advertise a shipping Widget or add an App Group dependency to the main app.

## Architecture

- `CycleEngine`: pure Foundation state/deadline model with an injectable `CycleClock`. Continuous elapsed time drives transitions; calendar time labels reminders and attributes statistics. It owns all cycle semantics.
- `TimerManager`: heartbeat and adapter for settings, environment, statistics and presentation. It never decrements a second counter or schedules delayed resume callbacks.
- `AppState`: observable UI projection, with no independent storage or lifecycle decisions. Display stopped, counting, paused, resting and physical-away states clearly; do not show completion pressure or reopen reminders through a hidden action.
- `ReminderPresentation`: pure display decisions for menu state, duration labels and visible action targets; native and SwiftUI menus share compact countdown/pause formatting.
- `StatisticsPresentation`: one calendar range for summaries, chart, daily rows and CSV. Missing days stay absent from exports; existing zero records remain distinct. The statistics view observes repository changes, not every timer heartbeat.
- `RestController`: translates engine progress into visual stages and forwards user actions. It does not own another timer.
- `RestManager` / `RestOverlayWindow`: render one non-activating overlay per display ID, using local content bounds. Background and text fade together. Any key and the visible return button dismiss immediately; never forward or replay the dismissal key. Do not activate the app or query/restore a foreground app. `DisplayLayout` reconciles display changes without restarting unaffected overlays. Removed windows invalidate queued actions.
- `WorkspaceMonitor`: physical lock/sleep lifecycle only. No foreground-app identification, call/video/fullscreen rules, inactivity polling or app allowlist. These removed features must not be reintroduced as “smart” interruption avoidance.
- `StatisticsManager`: one in-memory repository backed by a versioned UserDefaults snapshot. Inject defaults, calendar provider and clock for tests. Split work at observed time-zone changes and midnight; preserve already attributed date labels. The presentation consumes a single records/calendar/reference-date snapshot. Deduplicate completed rest UUIDs; merge overlapping legacy stores by per-field maximum. Flush periodically and at lifecycle boundaries.
- `WeeklyRecapManager`: removes legacy repeating notifications. Weekly notifications remain disabled until there is explicit opt-in and fresh content.
- `SharedDataAccess`: optional future Widget bridge, gated on the actual App Group signing entitlement.
- `AppSettings`: seconds-based rest duration, legacy minute migration, bounded persisted values and isolated defaults injection.
- `AppDelegate`: skips production startup/termination side effects in the XCTest host.
- `RelaunchIntentStore` / `RelaunchHandoff`: App Sandbox ignores `NSWorkspace.OpenConfiguration.arguments`. Language relaunch instead writes a one-time intent inside the app container, with a random token, predecessor PID/launch date, bundle ID and 30-second expiry. Only a newly launched process may consume it (allowing one second for LaunchServices date precision); atomically claim the file, validate the predecessor identity, and wait for that process to terminate before loading records, starting timers or registering shortcuts. Failed launches clear only their own token. Waiting processes cannot initialize runtime through termination, reopen or commands. The replacement opens Settings directly on General without relying on launch arguments.

## Behavior contract

The detailed, user-approved contract is `docs/product-contract.md`. Preserve these decisions:

- Reminder interval: 15–120 minutes, default 40. Break: 20–900 seconds, default 300. A 20-second break has a separate 2-second fade-in and 1-second fade-out.
- Automatic silent overlays are the only reminder style. No preliminary reminder panel or mode choice. Underlying videos, meetings, downloads and app tasks continue; do not send app/media control commands.
- Any key, Escape or Return to work immediately removes the overlay. Start a fresh full reminder interval after an early return, a skipped reminder or a naturally ended break. Do not keep the former five-minute repeat behavior.
- Pause presets are 1, 2 and 4 hours; custom pause is 1–1440 integer minutes. Work measurement continues during pause. Persist its deadline. On expiry or explicit resume, start a new full reminder interval instead of firing an overdue reminder.
- Stop removes overlays and stops work measurement. Persist the stopped state. Relaunch, preference edits, previews and secondary actions must not silently turn reminders back on. Do not offer a manual-break action that cancels a stop or pause.
- Physical lock/sleep stops work measurement and removes overlays without overriding the user's stop/pause. Returning after at least the configured break duration resets the interval; shorter absences retain the deadline with at least 60 seconds of recovery grace.
- Historical completed-rest fields remain timer facts, not targets or proof of rest. Do not change persisted counts to pretend early returns were full timed sessions. Keep neutral record explanations outside the primary reminder flow.
- Retain 90 calendar days of ordinary statistics. Preserve future-dated records on clock rollback and corrupt payload bytes before recovery. Date keys remain Gregorian with the local time zone; existing daily labels do not change with the system display calendar or a later time-zone change.

## UI and resources

- Use native black/white semantic colors from `Utils/Colors.swift`, clear typography and reachable controls. Respect Reduce Motion. Keep every overlay dismissible by its visible return button and any key, including Esc. Use “休息一下 / Take a break” and “返回工作 / Back to work”; do not center the product on “离屏休息”, completion, or a score.
- Localize all visible strings in `en`, `zh-Hans`, `ja` and `fr` resources, including plural forms and accessibility text. Shared localization, duration and plural helpers live in `Utils/Localization.swift`; SwiftUI dynamic strings require explicit localization (`L` or `LocalizedStringKey`). The first launch follows the system language, with English as the development fallback. Language changes apply after relaunch; preserve regional time conventions and stable CSV/storage formats.
- Settings use native grouped tabs and resizable windows. Let prominent button styles choose their label contrast in active and inactive windows; do not force white text. Explicitly left-align multiline Form footers.
- Closing settings/statistics/popover releases their observing SwiftUI trees; reopening recreates them. Keep the settings frame autosave. Coalesce menu-bar model publications on the next main-queue turn and avoid reassigning unchanged native properties; do not reduce engine heartbeat or rest countdown accuracy for UI performance.
- Onboarding uses a single draft and one commit action. Closing first-run setup exits without silently applying defaults; cancelling a later setup preserves existing preferences. It cannot require notification permission or enabling launch at login.
- Silence is an intentional product behavior. Do not add ambient audio, notification sounds, guided eye exercises, achievement prompts or proactive recaps.
- Preferences and records remain local; no account or backend. `LumenFocus.xcdatamodeld` is unused scaffold; do not introduce Core Data.
- Use `os.Logger` via `Log.*`; do not log keyboard contents, application identities or user activity histories.

## Testing and release boundaries

Use fake clocks and unique UserDefaults suites. Never test by resetting production singleton preferences. Add regression tests for observable behavior, especially transitions, interruptions, migrations and attribution across date boundaries. Native presentation tests create unordered windows with injected actions and Reduce Motion; any-key dismissal, non-activation and underlying-task continuity require explicit device checks. Automated window tests do not change the user's desktop. Run the shared scheme, release-script fixtures and universal Release Archive before proposing release changes.

Keep the App Store entitlement baseline narrow: App Sandbox and user-selected file read/write only. PrivacyInfo.xcprivacy declares no tracking/collected data and UserDefaults CA92.1. The release validator checks these against the source and built app. Changes to capabilities or data handling need an accompanying manifest, policy and validator review; do not add unused capabilities.

Physical multi-display layouts/hotplug, Spaces/fullscreen, lock/sleep, VoiceOver, minimum macOS and long-running energy use still need explicit device validation. A passing build or unit suite must not be described as evidence for those checks.
