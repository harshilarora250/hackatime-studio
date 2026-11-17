# Hackatime Studio — Design System

> **Concept: "the instrument and the file."**
> Studio is a precise instrument panel for your coding time that never hides the file it controls.
> Numbers are the heroes, one confident blue carries meaning, and every setting shows the real
> `.wakatime.cfg` key it writes.

Reference images supplied during planning (a utility-app settings window and a task manager) were
used only to calibrate density and calmness. No layouts, components, or visuals are copied.

---

## 1. Principles

1. **Clarity over decoration.** One accent colour, no ornamental gradients, minimal glass, no
   drop-shadow stacks. Every visual element must carry information.
2. **Show the source of truth.** Settings display their config key in a small mono *key tag*
   (`api_url`, `[projectmap]`). Users learn the real system while using the GUI.
3. **Honest states.** Never imply success that has not been verified. "Unknown / can't verify"
   is a first-class visual state, distinct from "OK".
4. **Native first, distinctive second.** Standard macOS behaviours (keyboard shortcuts, focus
   rings, menus, sheets, file pickers, toolbar placement, window resizing) are kept. Identity comes
   from typography, colour, spacing, and a few signature components, not from re-inventing
   controls.
5. **Progressive disclosure.** Basic first; Advanced is one click away and complete.

---

## 2. Colour system

All colours are defined as dynamic tokens in `UI/Design/Theme.swift`. Light and dark are designed
separately; dark is not an inversion. It uses blue-black surfaces and a lighter, slightly less
saturated accent so blue stays legible without glowing.

### Surfaces
| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `canvas` | `#F3F5F9` | `#0E1116` | window background behind content |
| `sidebar` | `#EAEEF5` | `#12161D` | sidebar column |
| `panel` | `#FFFFFF` | `#181C24` | primary content panels |
| `panelRaised` | `#F7F9FC` | `#1F2430` | wells, inputs, nested rows |
| `hairline` | `#0F172A` @ 7% | `#FFFFFF` @ 6% | the only divider/stroke colour |

### Ink (text)
| Token | Light | Dark |
| --- | --- | --- |
| `ink` | `#0F172A` | `#E8ECF4` |
| `inkSecondary` | `#475569` | `#A3ADBF` |
| `inkTertiary` | `#8591A5` | `#6B7588` |

### Accent: Signal Blue
| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `accent` | `#1D5BF0` | `#6B97FF` | primary actions, selection, focus |
| `accentSoft` | accent @ 11% | accent @ 16% | selection capsule, key tags, chip fills |
| `accentInk` | `#FFFFFF` | `#0B1020` | text on solid accent |

### Status (always paired with a shape glyph, never colour alone)
| State | Glyph | Light | Dark |
| --- | --- | --- | --- |
| OK | `checkmark.circle.fill` | `#13A26B` | `#3DD598` |
| Warning | `exclamationmark.triangle.fill` | `#C98200` | `#F5B83D` |
| Error | `xmark.octagon.fill` | `#D64045` | `#FF6B6E` |
| Unknown / unverifiable | `questionmark.circle` (outline) | `inkTertiary` | `inkTertiary` |
| In progress | spinning `arrow.triangle.2.circlepath` | `accent` | `accent` |

### Activity ramp (heatmap, bars)
Five steps, from "no activity" to the most active days:
* Light: `#E6EBF3`, `#BFD2FF`, `#85A9FF`, `#3D74F5`, `#1A4CC9`
* Dark: `#1C222D`, `#1E3366`, `#2A4FA8`, `#4677F0`, `#86A9FF`

Categorical charts (languages, projects) use language colours from the API when present (the
`color` field returned by `/api/v1/users/my/stats`). Otherwise they use a blue-anchored 6-colour
sequence: accent, teal `#14A3B8`, violet `#7C5CFF`, amber `#E5A13A`, rose `#E2557B`, slate
`#64748B`.

---

## 3. Typography

System fonts only (no bundled fonts). Three voices:

| Role | Font | Size / weight | Notes |
| --- | --- | --- | --- |
| Metric (hero numbers) | SF Pro **Rounded** | 34 / semibold | monospaced digits, `numericText` transitions |
| Metric small | SF Pro Rounded | 22 / semibold | widget values |
| Page title | SF Pro | 22 / bold | one per page |
| Headline | SF Pro | 14 / semibold | panel titles |
| Body | SF Pro | 13 / regular | default text |
| Callout | SF Pro | 12 / regular | descriptions |
| Caption | SF Pro | 11 / medium | metadata |
| Eyebrow | SF Pro | 10.5 / semibold, uppercase, +0.8 tracking | section labels above panels |
| Code | SF Mono | 11.5 / medium | key tags, paths, regexes, config preview |

Rule: anything that lives in a file (key, path, regex, value) is set in SF Mono.

---

## 4. Spacing, radii, sizing

* **Grid:** 4 pt. Scale: `4, 8, 12, 16, 20, 24, 32, 40`.
* **Page insets:** 28 pt horizontal, 24 pt top.
* **Panel padding:** 18 pt. **Gap between panels:** 16 pt. **Row height:** ≥ 36 pt.
* **Radii:** panels 16, inner wells and inputs 10, buttons 8, key tags and chips 6, heatmap cells 3.
  Corners are always `.continuous`.
* **Window:** min 980 × 640, default 1180 × 780. Sidebar fixed at 220 pt.

---

## 5. Components

* **Panel.** `panel` fill with radius 16. In light mode it has a 1 px hairline; in dark mode a
  1 px top highlight (`#FFFFFF` at 4%). No shadows. Optional eyebrow and title above it, outside the
  surface.
* **Key tag.** Small mono capsule with `accentSoft` fill and accent text, showing the config key a
  control writes. Hovering shows the section, e.g. `[settings] api_url`.
* **Status line.** Glyph, label and optional detail on one line. Used in Diagnostics, Editors and
  the setup flow.
* **Metric tile.** Eyebrow, hero number, then a secondary line (comparison or range).
* **Buttons.** `StudioButtonStyle`:
  * `.primary`: solid accent.
  * `.secondary`: `panelRaised` fill with a hairline.
  * `.quiet`: text only.
  * `.destructive`: error ink, solid only inside confirmation sheets.
  Height 30, radius 8, pressed scale 0.98.
* **Inputs.** Native `TextField` / `SecureField` / `Toggle` / `Picker`, placed in `panelRaised`
  wells so they read as part of the system rather than as bare default controls.
* **Option row.** Title and description on the left, control on the right, key tag under the
  title. A "Modified" dot appears when the value differs from the default; "Reset" removes the key
  from the file.
* **Segmented chips.** Used for ranges (Today / 7 days / 30 days / Year).

---

## 6. Navigation

A custom sidebar, not `NavigationSplitView` defaults:

```
 ◉ Hackatime Studio        ← wordmark + live connection dot
 ─
 Overview
   Dashboard          ⌘1
 Setup
   Configuration      ⌘2
   Folders & Projects ⌘3
   Editors            ⌘4
 System
   Diagnostics        ⌘5
 ─
 [ @username · Connected ]   ← status card; click → Diagnostics
 ⟳  Refresh   ⌘R    ⚙ Settings ⌘,
```

* The selection is an `accentSoft` capsule that **slides** between rows (`matchedGeometryEffect`,
  spring with response 0.32 and damping 0.86). Icons are monochrome SF Symbols; the selected icon
  takes the accent colour.
* Group labels are eyebrows. There are no dividers between rows.
* Settings (appearance, refresh cadence, dashboard defaults, uninstall) is a sidebar destination,
  pinned at the bottom.
* Each page has a header with the title, a one-line subtitle, and page actions aligned right.

---

## 7. Dashboard layout

* A responsive **4-column grid** that collapses to 2 columns below 1000 pt of content width.
  Widgets declare a span: `small` (1), `medium` (2) or `wide` (full row).
* Default order:
  1. Today (small)
  2. This week (small)
  3. This month (small)
  4. Streak (small)
  5. Activity graph (wide)
  6. Languages (medium)
  7. Projects (medium)
  8. Daily goal (small)
  9. Tracking status (small)
  10. Recent activity (medium)
* **Customise** opens a sheet. In it you can toggle widgets, drag to reorder, change per-widget
  settings (range, item count, graph length), and use **Restore defaults**.
* An unavailable metric shows a muted inline explanation and the reason. It never shows a
  zero that looks like real data.

### Activity graph
A grid of 7 rows (weekdays) by N weeks with month labels above and weekday labels at the left. The
ramp is quantised by quartiles of the user's own non-zero days, so light and heavy coders both get
a readable graph. Hovering a cell shows the date and exact duration. A legend reads "Less ▢▢▢▢▢
More".

---

## 8. Light & dark

* **Light:** a cool off-white canvas, white panels, hairlines for structure, deep Signal Blue.
* **Dark:** blue-black layering (canvas → sidebar → panel → raised) does the structural work
  instead of strokes. The accent is lifted to `#6B97FF`. The heatmap ramp starts from a desaturated
  navy so empty days recede.
* **Appearance setting:** System / Light / Dark. It is applied app-wide through `NSApp.appearance`,
  so every dynamic token updates live.

---

## 9. Interaction patterns

* **Refresh (⌘R)** behaves like a browser reload. It refetches the API, reloads the config from
  disk, rechecks editors, and reruns diagnostics. The icon rotates while work is in flight. Dashboard
  data also refreshes automatically (default every 5 minutes while the app is active, configurable),
  and after the Mac wakes or the window becomes key, if the data is stale.
* **Edits save immediately** to `.wakatime.cfg`. Text fields save on commit (Return / focus loss),
  not on every keystroke. A short toast confirms the save ("Saved to ~/.wakatime.cfg"), with an
  "Undo" that restores the previous backup.
* **Destructive actions** (remove extension, uninstall, replace API key) always open a sheet that
  lists exactly what will change, with the destructive button on the trailing side.
* **External changes** to the config file are picked up live, with a subtle banner: "Reloaded,
  changed outside Studio".
* **Secrets** are masked by default (`waka_••••••••3f9a`). A reveal toggle shows the key in place
  for that view only.

---

## 10. Motion

| Moment | Animation |
| --- | --- |
| Sidebar selection | sliding capsule spring (0.32 / 0.86) |
| Page switch | 0.18 s cross-fade plus a 6 pt upward offset |
| Numbers changing | `.contentTransition(.numericText())` |
| Heatmap first load | cells fade in by column, 0.35 s total |
| Panels appearing | opacity with a 0.98 → 1 scale, 0.2 s ease-out |
| Hover | 0.12 s ease-out background tint |
| Refresh | continuous rotation while loading |

When **Reduce Motion** is on, every spring and offset becomes a plain cross-fade and the heatmap
stagger is disabled.

---

## 11. Accessibility

* Text and icon contrast meets WCAG AA in both appearances. Tertiary ink is used only for
  non-essential metadata.
* Status is never shown by colour alone: a glyph shape and a text label are always present.
* Every icon-only button has an accessibility label and a tooltip.
* Heatmap cells are accessibility elements with labels such as "Monday 3 November: 2 hours
  14 minutes".
* Full keyboard navigation: sidebar shortcuts, ⌘R, ⌘, and standard focus rings on all controls.
* API keys are never read aloud in full; VoiceOver reads the masked form.
