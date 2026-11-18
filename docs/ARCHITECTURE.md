# Hackatime Studio — Architecture & Implementation Plan

Hackatime Studio is a native macOS GUI for the existing Hackatime / WakaTime ecosystem.
It does not track time itself. It reads and edits the real `.wakatime.cfg`, talks to the
real Hackatime API, and inspects the real editor + `wakatime-cli` installation.

## 1. Starting point

The repository began as an untouched Xcode 26.6 SwiftUI template (`desktop_atimeApp.swift` (now `HackatimeStudioApp.swift`),
`ContentView.swift`, Swift 6.3 compiler in Swift 5 language mode, macOS 26.5 deployment target,
default actor isolation = `MainActor`, file-system-synchronised groups). Both files are kept and
extended: the `App` struct becomes the Studio entry point and `ContentView` the root view.

Project-level changes:

| Change | Why |
| --- | --- |
| App Sandbox disabled | Studio must read/write `~/.wakatime.cfg`, inspect `~/.wakatime/`, `~/.vscode/extensions`, and run VS Code's `code` CLI. Studio ships outside the Mac App Store. |
| Display name `Hackatime Studio` | Project, targets, scheme and product are named `Hackatime Studio`; the bundle identifier is unchanged. |
| `Hackatime StudioTests` unit-test target (Swift Testing) | Config parsing/writing, project rules, API decoding, detection. |

## 2. Verified facts the design depends on

Sources: `hackclub/hackatime` (routes, controllers, docs), `wakatime/wakatime-cli` (`USAGE.md`,
`pkg/params`, `pkg/ini`, `pkg/project`), `hackclub/vscode-hackatime`, `wakatime/vscode-wakatime`,
`go-ini/ini` v1.67 parser.

### Config file
* Location order used by wakatime-cli: `--config` → `$WAKATIME_HOME/.wakatime.cfg` → existing
  `~/.wakatime.cfg` → `$XDG_CONFIG_HOME/wakatime/wakatime.cfg` (default `~/.config/wakatime/wakatime.cfg`).
* Both VS Code extensions read `$WAKATIME_HOME/.wakatime.cfg` or `~/.wakatime.cfg` **directly**
  (never the XDG path). Studio therefore creates `~/.wakatime.cfg` when nothing exists and warns
  when only an XDG file exists.
* Parsed by `go-ini` with `AllowPythonMultilineValues`: a key with an empty value followed by
  indented lines is a list; `#`/`;` anywhere in an unquoted single-line value starts a comment; a
  `[` line without `]` is dropped; a line without `=`/`:` makes the whole file fail to load.
* Viper lowercases keys, so section and key matching is case-insensitive.
* `[projectmap]` is loaded from a Go map → **iteration order is not deterministic** (despite the
  docs saying "first match wins"). Studio only generates non-overlapping patterns.
* All regexes (`exclude`, `include`, `projectmap`, …) are made case-insensitive by the CLI and fall
  back to `regexp2`, so look-ahead is supported.
* Project detection priority: `.wakatime-project` file → `[projectmap]` → git → editor workspace.

### Hackatime API (API-key authenticated)
| Endpoint | Auth | Used for |
| --- | --- | --- |
| `GET {api_url}/users/current` | Bearer / Basic / `?api_key` | key validation, username, timezone |
| `GET {api_url}/users/current/statusbar/today` | same | today total, **daily goal** progress |
| `GET {api_url}/users/current/summaries?start&end` | same | per-day totals + per-day projects (≤ 366 days) → activity graph, week, month, recent days |
| `GET {host}/api/v1/users/my/stats?features=languages,projects&start_date&end_date` | Bearer API key | language + project breakdown, **streak** |
| `GET {host}/api/v1/users/my/heartbeats/spans?start_date&end_date` | Bearer API key | today's coding sessions |
| `GET {host}/api/v1/my/heartbeats/most_recent[?editor=vscode]` | Bearer API key | last heartbeat / tracking verification |

### Lapse API (public, unauthenticated)
Source: `hackclub/lapse` (`packages/api/src/contracts`). Base `https://api.lapse.hackclub.com/api`; responses are
`{ok, data}` / `{ok:false, error, message}`. Protected routes take Lapse OAuth tokens (PKCE, registered app) or
staff program keys, **never Hackatime keys**. Studio uses only:

| Endpoint | Used for |
| --- | --- |
| `GET /user/query?hackatimeId=N` | Lapse profile linked to the Hackatime `users/current` `id` (`null` if none) |
| `GET /timelapse/findByUser?user=ID` | the user's PUBLIC timelapses; `playbackUrl` is a public MP4/WebM, `createdAt` is ms epoch, `duration` is seconds recorded |

Not available with an API key: weekly/custom goals (only the daily goal is exposed), the
`/api/v1/authenticated/*` endpoints (OAuth only). Studio says so in the UI instead of inventing data.

### Editor integration
* Official VS Code extension: `hackatime.hackatime-time-tracker` ("Hackatime Time Tracker").
  `WakaTime.vscode-wakatime` is compatible. Both installed = double heartbeats (warned).
  `WonkyStudio.hackatime` is the unofficial extension the docs warn against.
* Both extensions download `wakatime-cli` into `~/.wakatime/` (`wakatime-cli-darwin-<arch>` +
  `wakatime-cli` symlink). Logs live in `~/.wakatime/wakatime.log`; offline queue in
  `~/.wakatime/offline_heartbeats.bdb`.

## 3. Module layout (`Hackatime Studio/`)

```
App/            AppModel (single @Observable store), AppRouter, refresh scheduler
Core/Config/    INIDocument (lossless parser/writer), ConfigLocator, ConfigStore
                (backups, atomic writes, external-change detection), ConfigSchema
                (every verified option), ProjectRules (folders ⇄ projectmap/exclude)
Core/API/       HackatimeClient, API models, error mapping (key-safe)
Core/System/    ProcessRunner, ShellEnvironment, WakatimeInstallation, Redaction, StudioPaths
Core/Editors/   EditorIntegration protocol, VSCodeIntegration
Core/Diagnostics/ DiagnosticsEngine
Core/Uninstall/ UninstallPlanner / executor, StudioLedger (what Studio itself installed/created)
Core/Dashboard/ widget catalogue, persisted layout, aggregated dashboard data
UI/Design/      tokens (colour, type, spacing, radii, motion) + shared components
UI/<Feature>/   Sidebar, Dashboard, Configuration, Editors, Diagnostics, Settings, Onboarding
```

## 4. Config editing model

1. `INIDocument` keeps every original line (comments, blank lines, unknown keys, malformed lines).
2. Edits are expressed as operations (`set`, `remove`) on `(section, key)`.
3. `ConfigStore.apply(_:)` re-reads the file from disk, applies the operations to the fresh copy
   (so external edits are never lost), backs up the previous file to
   `~/Library/Application Support/Hackatime Studio/Backups/` (0600, last 30 kept), writes a temp
   file next to the target, then atomically replaces it. Symlinked configs are written through to
   their target. Permissions are preserved (new files: 0600).
4. A file-system watcher reloads the document when another tool edits it.

## 5. Milestones
1. Inspection + research (done) → 2. this plan → 3. `DESIGN.md` → 4. config core + tests →
5. API client + key validation → 6. setup flow → 7. VS Code integration → 8. folders & projects →
9. dashboard → 10. diagnostics + refresh → 11. uninstall → 12. polish + verification.
