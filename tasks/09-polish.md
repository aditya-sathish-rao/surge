# 09 - Per-surface polish

Phase 5. Up to three agents at once, one per surface. Start after tasks 05, 07 and 08 are merged.

Read: TRD sections 14 and 15 (Phase 5). Design file sections "Motion", "Accessibility and keyboard", "Writing". Skills: `swiftui-animation`, `ios-accessibility`, `apple-design`.

| Agent | Owns | Branch |
| --- | --- | --- |
| A | Popover and panel view files in `App/SurgeMenuBarApp/` | `feat/polish-popover` |
| B | Widget view files in `Widget/SurgeWidget/` | `feat/polish-widget` |
| C | Menu bar item files in `App/SurgeMenuBarApp/` | `feat/polish-menu-bar` |

Do not edit the shared Fuse or row components in `SurgeUI`. Request changes from the one named owner of those components.

## Each agent covers

- **Motion**: one choreographed moment only. When an agent stalls the fill stops and the hatch fades in over 0.3 s. On recovery the hatch clears left to right in a 0.4 s spring. No looping animation, no spinners, no pulses. Menu bar never animates. Reduce Motion turns everything into a cross-fade.
- **Accessibility**: one VoiceOver element per row, tabs as a proper tab group, `AXChartDescriptor` on charts, Increase Contrast variants, Differentiate Without Color (symbol plus word plus pattern for every state), keyboard shortcuts (Cmd+1, 2, 3 for tabs, arrows to move, Return to expand, Cmd+C for session ID, Cmd+, for Settings, Esc to close).
- **Copy**: the writing rules. Agents, Orchestrator, Worker, Workspace, Working, Waiting for you, Stalled. Title Case for buttons and menu items, sentence case elsewhere. No all caps.

## Check by running

Look at it. Light and dark, Increase Contrast, Reduce Motion, Reduce Transparency, larger system text. Fix anything that looks off, even outside the task, if it is inside your own files.

## Definition of done

Each surface passes the accessibility floor in PRD 11.1, tests and lint pass, no edits outside the agent's own files.
