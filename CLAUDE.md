# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal macOS menu bar app (status item next to the clock) that watches the owner's Claude subscription limits:

- **5-hour session limit** – notify when close to it and when it is hit; show when it resets.
- **Weekly limit, paced as a daily budget over workdays** – so the week's allowance lasts until the weekly reset. Notify when today's budget is nearly used and when it is exceeded.
- **Menu bar label** – text like `◐ 5h 82%  den 64%`.
- **Dropdown** – progress bars and reset times (local time) for every limit.

UI text is Czech. The full requirements, with notification kinds, acceptance criteria and open questions, are in `docs/requirements.md` (Czech).

## Commands

```
swift build                                   # debug build of both targets
scripts/test.sh                               # all tests (Swift Testing)
scripts/test.sh --filter EngineTests          # one suite or test
swift run ClaudeStatus --dump                 # one live fetch printed to stdout; saves nothing, no notifications
scripts/bundle.sh                             # build/ClaudeStatus.app (release, ad-hoc signed)
scripts/bundle.sh --install                   # also copy to ~/Applications and launch from there
log stream --info --predicate 'subsystem == "local.ClaudeStatus"'   # live app log
```

Always run tests through `scripts/test.sh`; plain `swift test` fails on this machine (see Toolchain constraints).

## Architecture

The full design is in `docs/design.md` (Czech).

- **Two targets.**
  - `ClaudeStatusCore` is a library that imports only Foundation. It holds all logic and has no side effects except through injected ports (`TokenProviding`, `UsageFetching`, `Notifying`, `StateStoring`).
  - `ClaudeStatus` is the executable: SwiftUI UI plus the platform adapters (security CLI, URLSession, UserNotifications, SMAppService, wake observer).
- **Every decision goes through one pure function, `Engine.step(StepInput) -> StepOutput`.** It maps the API response, updates baselines and samples, computes the `Snapshot`, and decides which notifications to send, including dedupe. `UsageMonitor` (`@MainActor @Observable`) only does the IO around it. The acceptance criteria in `docs/requirements.md` map to Engine tests.
- **Core builds the user-facing strings:** the menu bar text and the notification texts (`cs_CZ`, 24-hour time). UI views only display them.
- **State is one Codable `PersistedState`** under the key `state.v1`, with settings under `settings.v1`, both in `UserDefaults(suiteName: "local.ClaudeStatus.state")`. The explicit suite makes `swift run ClaudeStatus --dump` read the same store as the bundled app. The suite must not equal the bundle ID `local.ClaudeStatus`, because a suite named after the app's own bundle ID does not work. `--dump` (`UsageMonitor.dryRun`) is a dry run: one fetch, snapshot printed to stdout, nothing saved, no notifications.
- **Settings live inside the dropdown panel**, not in a SwiftUI `Settings` scene. That avoids the settings window opening behind other apps in an `LSUIElement` app.
- **The login item is registered only from `~/Applications` or `/Applications`** (`LoginItem.isInstalledLocation`). A build running from `build/` skips it.
- **Install the bundle to `~/Applications`, not into this repo.** The repo is on an encrypted volume, and a login item pointing there fails if the volume is not mounted yet. The repo path also contains non-ASCII characters (`Šifrovaný disk`), so quote paths in scripts.

## Toolchain constraints (this machine)

- **No Xcode, only Command Line Tools** (Swift 6.2.3, macOS 26). `xcodebuild` fails, so this is a **SwiftPM-only** project with no `.xcodeproj`.
- **Stack:** Swift 6, SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`, Observation (`@Observable`), deployment target `.macOS(.v14)`.
- **Notifications need an app bundle.** `UNUserNotificationCenter` crashes in a bare executable, which has no bundle identifier, so `swift run` is not enough for real runs. The build has to:
  1. wrap the release binary in an `.app`, with an `Info.plist` that sets `CFBundleIdentifier` and `LSUIElement = true` (no Dock icon);
  2. ad-hoc sign it with `codesign --force --sign -`.

  Keep these steps in one script.
- **Tests use Swift Testing** (`import Testing`); XCTest is not available. `scripts/test.sh` works around two CLT gaps:
  - SwiftPM does not find the CLT copy of `Testing.framework`, so the script passes `-F` and `-rpath` for `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`.
  - CLT ships `_Testing_Foundation.framework` without its module interface, so any test file importing both Testing and Foundation fails with "no such module '_Testing_Foundation'". The script passes `-Xfrontend -disable-cross-import-overlays`.

  Without `platforms: [.macOS(.v14)]` in the manifest, the test macros fail to compile ("only available in macOS 10.15 or newer").
- **Test fixtures** in `Tests/ClaudeStatusCoreTests/Fixtures/` are a real captured response (`usage-full.json`) and two variants derived from it. When the API shape changes, capture a new response with the token piped straight from `security`, never written to disk, and check it for identifiers before committing.

## Data source

The only source is the undocumented endpoint that Claude Code itself uses for `/usage`:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
```

### Token

The token lives in a Keychain generic password with service `Claude Code-credentials` (account = macOS user name). The value is JSON. Use only `claudeAiOauth.accessToken` and `claudeAiOauth.expiresAt`; `expiresAt` is in **milliseconds** since 1970. The other keys (`mcpOAuth`, `refreshToken`, …) belong to Claude Code.

- **Read it by running `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`** through `Process`. This reads without a prompt because the item's ACL trusts `security`. `SecItemCopyMatching` from an ad-hoc-signed app would likely trigger a Keychain prompt again after every rebuild.
- **Read-only.** Never refresh the token and never write the item. Claude Code rotates the token itself, and a refresh from here could invalidate its session. Re-read the token before each poll and after a 401. If the token has expired, show a state that tells the user to open Claude Code.

### Response shape

Verified 2026-10-15. The endpoint is undocumented and changes without notice.

- **Use `limits[]` first.** Each entry has `kind`, `group`, `percent` (Int 0–100), `severity` (`"normal"`, `"warning"`, …), `resets_at`, `scope` and `is_active`. The meaning of `is_active` is unclear, so do not rely on it. Kinds seen so far:
  - `session` – the 5-hour limit;
  - `weekly_all` – the weekly limit;
  - `weekly_scoped` – a per-model weekly cap; the model name is in `scope.model.display_name`, and `weekly_scoped_shares[]` gives the cap as a share of the weekly limit.
- **Fall back to the flat objects** `five_hour` / `seven_day`. They have `utilization` (a Double from 0 to 100, not 0 to 1) and `resets_at`. Community reports say these were `null` for a while, so either shape may be missing.
- **`seven_day_breakdown.window_started_at`** is the start of the current weekly window. The window is fixed: start + 7 days = `resets_at`. It does not roll.
- **`extra_usage` / `spend`** describe paid overage (EUR) that applies once limits are hit, so hitting a limit can mean spending money. **Amounts are in minor units:** `spend.used.amount_minor: 235` with `exponent: 2` is 2.35 €. Likewise, `extra_usage.used_credits` uses `decimal_places`.
- **The response also has dozens of codename keys** (`iguana_necktie`, `tangelo`, …), mostly `null`. Ignore them. Decode leniently: every field optional, unknown keys ignored, and each nested field decoded with `try?` in a custom `init(from:)`. Plain `decodeIfPresent` throws on a type mismatch and would fail the whole response. That way a schema change breaks one bar instead of the whole app.
- **`resets_at` comes both with and without fractional seconds** (`…T19:59:59.993971+00:00` and `…T20:00:00+00:00`). Parse both forms. The same reset also jitters between calls by fractions of a second, across the minute boundary (`19:59:59.99` vs `20:00:00.42`). **Always round to the nearest minute, never truncate**, both for display and for window keys (`WindowKey`).
- **Polling:** at most once every 60 s. Back off on errors and on 429.

## Daily budget (derived; the API has no daily limit)

The weekly allowance is spread over **workdays only (Mon–Fri)**. Budgets roll over: unused budget moves to later days, and overspending shrinks them.

- **Weights.** `w(day)` is the part of a workday that lies inside the current weekly window, divided by **that day's actual length**: DST days are 23 or 25 h long, so do not divide by a fixed 24 h. Saturday and Sunday weigh 0. The window is `[resets_at − 7 × 86 400 s, resets_at]` in absolute time, so the local reset time shifts across DST (22:00 → 21:00). The reset day (currently Tuesday 22:00 local) is split between the old window and the new one. A window adds up to about 5 workday units; always use the computed sum, never the constant 5.
- **Baseline** `B` = the weekly percent at the first poll of the local day. Persist it together with the date. Take a new baseline when the weekly window resets, which shows as `resets_at` moving forward or the percent dropping below `B`.
- **Today's budget:** `todayBudget = (100 − B) × w(today) / Σ w(d)`, summed over the days from today through the reset day.
- **Today's usage:** `todayUsed = weekly percent − B`. The label shows `todayUsed / todayBudget`, which can exceed 100 %.
- **Weekend usage** has no budget of its own. It lowers the following workdays' budgets through `B`.
- **The local day starts at midnight.** Public holidays and vacations count as workdays; there is no calendar data.
- **"On plan"** for the weekly-pace warning uses the same weights: expected % = 100 × Σ w(window start … end of today) / Σ w(whole window). That is the share allocated through the end of today.
- Known limitation: if the app starts mid-day, usage from earlier that day is counted in `B` instead of `todayUsed`.

## Notifications

The nine notification kinds, their thresholds and their frequencies are listed in `docs/requirements.md` (F4). Implementation rules:

- **Banner style**, which is the macOS default; do not set `NSUserNotificationAlertStyle`. Only the "reached" kinds (#2, #6) play a sound.

- **Fire each notification at most once per window, or once per day for the daily kinds.** The dedupe key is the kind + the window + the threshold. The window is `resets_at` rounded to the minute, or the local date for the daily kinds. Persist the keys in `UserDefaults` so that a restart does not repeat notifications.
- **Show times in local time.** Notification text includes the reset time.
