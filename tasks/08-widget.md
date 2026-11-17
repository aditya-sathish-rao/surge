# 08 - Desktop widget (SurgeWidget)

Phase 4B. Needs only `SurgeCore` and `SurgeUI`, and the frozen `SurgeSnapshot` shape. Can run in parallel with task 07 against a hand-written fixture snapshot. Owns only `Widget/SurgeWidget/`. Branch: `feat/widget`.

Read: PRD sections 7.3, 8. TRD sections 4, 6.2, 6.4. Design file section "Desktop widgets". Skill: the `widgetkit` skill.

## Goal

Replace the placeholder in `Widget/SurgeWidget/SurgeWidget.swift` with the real widget. One widget kind, "Surge", in Small, Medium and Large.

## Key requirements

- Only read the `SurgeSnapshot` file from the App Group container. No pipeline, no state store, **no networking of any kind**.
- Small: is anything wrong? One number (agents working) and four mini Fuses, or the name and state of the agent that needs you.
- Medium: the four most urgent agents or sub-agents, one row each, plus account balances.
- Large: the full agent tree for the workspace, a 7-day spend chart, and balances. More information, not a stretched Medium.
- Configurable per widget instance: all workspaces or one project (AppIntent configuration; the scaffold uses `StaticConfiguration`).
- No buttons. Clicking anywhere opens the panel at the relevant place.
- Placeholder before first data: grey capsules and grey text bars.
- Text at least 11 pt. Readouts use expanded width. Use `.containerBackground(.fill.tertiary, for: .widget)` and `ContainerRelativeShape`. Cards stay dark in both appearances (PRD).
- Gallery description: "See which coding agents and sub-agents are working, waiting for you, or stalled, plus today's spend and account balances."

## Live feel inside the system budget (TRD 6.2)

- Elapsed labels ("Stalled 3m 14s", "Idle 4m") use `Text(timerInterval:)` or `Text(_:style: .timer)`. The system ticks them without a new timeline entry.
- Show "Updated 2 min ago" when `generatedAt` is more than 5 minutes old. Never show stale data as if it were live.
- Data changes use `.contentTransition(.numericText())`, under 2 seconds.

```swift
Text(stall.startDate, style: .timer)          // system-refreshed timer
.containerBackground(.fill.tertiary, for: .widget)
```

## Local MVP note: no App Group yet

See the same note in task 07. Read the snapshot through the shared location type, never a hard-coded path in widget code.

## Business logic to test

- Choosing the four most urgent agents from a snapshot
- Staleness: when "Updated N min ago" appears and its wording
- Small widget content choice: working count versus the agent that needs you
- Workspace filter selection
- Missing or corrupt snapshot file falls back to the placeholder, never a crash

## Ask the user before deciding

- Where to open the app at tap (deep link format) once task 07 defines it.
- The Large widget workspace when the filter is "All".

## Definition of done

Widget appears in Edit Widgets, renders all three sizes from a fixture snapshot in light and dark, tests and lint pass, nothing outside the target touched.
