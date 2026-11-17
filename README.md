# Hackatime Studio

A native macOS (SwiftUI) GUI for the existing [Hackatime](https://hackatime.hackclub.com) / WakaTime
ecosystem. It edits the real `~/.wakatime.cfg`, talks to the real Hackatime API, and manages the
VS Code extension. It never tracks time itself.

- Design system: [DESIGN.md](DESIGN.md)
- Architecture, verified API/config facts, and plan: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Build & test

Open `Hackatime Studio.xcodeproj` in Xcode 26+ and run the `Hackatime Studio` scheme (macOS 26.5+). From the
command line:

```bash
xcodebuild test -project "Hackatime Studio.xcodeproj" -scheme "Hackatime Studio" -destination 'platform=macOS'
```

The app is **not sandboxed**: it needs to read and write `~/.wakatime.cfg` and `~/.wakatime/`, and
run VS Code's `code` CLI. It can be distributed directly or notarized, but not through the Mac App
Store.

## Desktop widgets

The `Hackatime Studio Widgets` extension adds **Coding Activity** (small: 8 weeks, medium: 16 weeks)
and **Daily Goal** (small, medium) widgets. Right-click the desktop → *Edit Widgets…* → Hackatime Studio.

The extension is sandboxed and never sees the API key. After every dashboard refresh the app writes
a small snapshot (`Shared/WidgetSnapshot.swift`) to the App Group container
`~/Library/Group Containers/FU24QF42S6.xyz.elipseday.hackatime-studio/` and reloads the widgets, so
they update while Studio is running. Between refreshes they roll over at midnight (goal resets) and
show “Updated …” once the data is over two hours old. Colours come from `Shared/Palette.swift`, which
the app's `Theme` also uses.

## Developer tools (Debug builds only)

- `WAKATIME_HOME=/some/dir` points Studio at a scratch config instead of your real one. wakatime-cli
  honours this variable too.
- `STUDIO_SNAPSHOT_DIR=/out` renders every page in light and dark mode to PNGs, then quits.
  `STUDIO_SNAPSHOT_ROUTES=dashboard,folders` and `STUDIO_SNAPSHOT_SETUP=enterKey|success|guided0…3`
  narrow what is captured.
- `STUDIO_DEBUG_WIDGET_SAMPLE=1` writes sample data for the desktop widgets, then quits.
- `STUDIO_DEBUG_SETUP_KEY=<key>` runs the real verify-and-save setup path, then quits.
