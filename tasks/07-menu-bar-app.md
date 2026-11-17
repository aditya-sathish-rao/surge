# 07 - Menu bar app (SurgeMenuBarApp)

Phase 4A. Needs `SurgeStateStore` and `SurgeUI`. Owns only `App/SurgeMenuBarApp/`. Branch: `feat/menu-bar-app`.

Read: PRD sections 7.1, 7.2, 7.4, 7.5, 8. TRD sections 6, 10, 11, 12. Design file sections "Menu bar extra", "Popover and panel".

## Goal

Replace the placeholder in `App/SurgeMenuBarApp/SurgeApp.swift` with the real app: menu bar item, popover and detachable panel, settings, notifications, and the snapshot writer for the widget.

## Key requirements

- `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Label is a template glyph of up to four vertical mini-Fuses. Switches to an attention glyph when anything needs you. Never animates. Optional short readout (see questions).
- Popover is 360 pt wide with Agents, Usage and Spend tabs (compose `SurgeUI`). Dragging it off detaches it to a floating panel titled "Surge". Header says "N need you" or "All agents working", with today's spend as the hero number.
- Row interaction: Return expands inline. Secondary click offers Copy Session ID, Mute Alerts for This Agent, Reveal Working Directory in Finder. No action touches an agent.
- "More" menu: Pause Monitoring, Settings, Quit Surge.
- Settings window: global toggle shortcut (user-defined, no default), per-model stall threshold override, notification opt-ins (stall as Time Sensitive, completion as Passive), per-account low and empty thresholds (default $5 and $0.50).
- Notifications: Active for "waiting for you" always. Stall is Active, or Time Sensitive if opted in. Done is Passive if opted in. Nothing for working, idle or compacting. Never use a popover for a warning.
- The app stays non-sandboxed and uses hardened runtime. It has no Dock icon (`LSUIElement`).

## Snapshot and widget reload policy (TRD 6.2)

One background task in this target (not in the actor) owns it:

1. On every state change, serialise a `SurgeSnapshot` to the App Group container atomically (write a temp file, then rename). Coalesce writes to at most once every 5 seconds.
2. Call `WidgetCenter.shared.reloadTimelines(ofKind:)` at most once every 60 seconds, and only if since the last reload: an agent crossed working, waiting, stalled or done; or a wallet poll completed; or the user opened the popover.
3. Never reload on every token update. That exhausts the budget within minutes.

```swift
MenuBarExtra { DashboardView() } label: {
    Image("surge.fuses", variableValue: peakContext)   // custom template symbol
}
.menuBarExtraStyle(.window)
```

## Local MVP note: no App Group yet

Signing is deferred, so the App Group entitlement cannot be used. Put the snapshot behind one small location type in `SurgeCore` so it can move to the App Group later with a one-line change. For local MVP runs, the app writes to `~/Library/Application Support/Surge/snapshot.json` and the widget reads it through a read-only sandbox exception for that path. Confirm this with the user before building it, since the TRD specifies the App Group.

## Business logic to test

- Snapshot debouncing: many state changes inside 5 seconds produce one write
- Reload trigger rules and the 60-second ceiling
- Atomic write never leaves a partial file readable
- Notification level chosen for each state and opt-in combination
- Menu bar readout text and the accessibility label ("Surge. 5 agents, 2 need you. 16 dollars 91 spent today.")

## Ask the user before deciding

- Decided: use the PRD short text readout. If it is too wide for a crowded menu bar, tell the user rather than switching to one number.
- What "Reset Today's Counters" does, if at all (design file only).
- App icon: placeholder until supplied.

## Definition of done

Run it with `make run`. Menu bar item, popover, detach, settings and notifications work against the real state store. The snapshot file appears at the agreed local location. Tests and lint pass.
