# LumenFocus development guide

LumenFocus is a local macOS menu-bar app that reminds users to take breaks away from the screen. The default reminder is a non-activating panel; users can explicitly choose automatic immersive dimming. It does not measure eye health or prove that a user looked away.

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

- GitHub Actions builds/tests Debug and builds a universal unsigned Release. Signing, notarization and distribution are separate release gates.
- Widget sources are not integrated into a target. Do not advertise a shipping Widget or add an App Group dependency to the main app.

## Architecture

- `CycleEngine`: pure Foundation state/deadline model with an injectable `CycleClock`. Continuous elapsed time drives transitions; calendar time labels reminders and attributes statistics. It owns all cycle semantics.
- `TimerManager`: heartbeat and adapter for settings, environment, statistics and presentation. It never decrements a second counter or schedules delayed resume callbacks.
- `AppState`: observable UI projection, with no independent storage or lifecycle decisions.
- `RestController`: translates engine progress into visual stages and forwards user actions. It does not own another timer.
- `RestManager` / `RestOverlayWindow`: render the gentle reminder or one overlay per display, use local content bounds and retain exit controls throughout the rest. Freeze display selection before activating windows and restore the previous application's focus after dismissal.
- `WorkspaceMonitor`: local foreground-app and idle rules plus physical lock/sleep signals. The app allowlist is not real call, screen-share or fullscreen detection. Settings must apply live and survive relaunch.
- `StatisticsManager`: one in-memory repository backed by a versioned UserDefaults snapshot. Inject defaults, calendar and clock for tests. Split work at midnight; deduplicate completed rest UUIDs; merge overlapping legacy stores by per-field maximum. Flush periodically and at lifecycle boundaries.
- `WeeklyRecapManager`: removes legacy repeating notifications. Weekly notifications remain disabled until there is explicit opt-in and fresh content.
- `SharedDataAccess`: optional future Widget bridge, gated on the actual App Group signing entitlement.
- `AppSettings`: seconds-based rest duration, legacy minute migration, bounded persisted values and isolated defaults injection.
- `AppDelegate`: skips production startup/termination side effects in the XCTest host.

## Behavior contract

- Work interval: 15–120 minutes; default 40. Rest: 20–900 seconds; default 300. A 20-second rest means 20 seconds of rest plus 2 seconds dimming and 1 second brightening.
- Upcoming reminder + N minutes: move the effective deadline by N. Due reminder or active rest + N: remind N minutes from now.
- Pause suppresses reminders until a specified time; work measurement continues. Resume retains the prior due time with at least 60 seconds of recovery grace. It does not override environmental suppression.
- Skip explicitly starts another full work interval. Early cancellation is not completion: keep the original work deadline and allow at least five minutes before reminding again.
- Foreground-app rules suppress reminders but continue measuring work. No keyboard/mouse input is not proof of rest; it only downgrades automatic immersive reminders to gentle prompts.
- Physical lock/sleep stops work measurement regardless of optional avoidance preferences. Returning after at least the configured rest duration resets the interval without adding a guided completion. Short absences retain the due time and allow recovery grace.
- Only completed guided rest sessions increment the completed-rest count. Statistics are timer activity, not measured screen exposure or health scores.
- Retain 90 calendar days of ordinary statistics. Preserve future-dated records on clock rollback and preserve corrupt payload bytes before recovery.

## UI and resources

- Use native black/white semantic colors from `Utils/Colors.swift`, clear typography and reachable controls. Respect Reduce Motion. Keep every overlay dismissible by visible buttons and Esc.
- Localize all visible strings in `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`. SwiftUI dynamic strings require explicit localization (`L` or `LocalizedStringKey`).
- Onboarding is optional and scrollable with fixed navigation. It cannot require notification permission or enabling launch at login.
- Audio assets are absent: do not expose nonfunctional sound choices. Breathing/visual exercise scaffolds are not part of the default break flow.
- Preferences and records remain local; no account or backend. `LumenFocus.xcdatamodeld` is unused scaffold; do not introduce Core Data.
- Use `os.Logger` via `Log.*`; do not log foreground application identities or user activity histories.

## Testing and release boundaries

Use fake clocks and unique UserDefaults suites. Never test by resetting production singleton preferences. Add regression tests for observable behavior, especially transitions, interruptions, migrations and attribution across date boundaries. Run the shared scheme and universal Release build before proposing release changes.

Physical multi-display layouts/hotplug, Spaces/fullscreen, lock/sleep, VoiceOver, minimum macOS and long-running energy use still need explicit device validation. A passing build or unit suite must not be described as evidence for those checks.
