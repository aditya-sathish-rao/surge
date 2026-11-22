# Tasks

One file per work stream, taken from the TRD build plan (section 15). Hand one file to one agent. Every file is self-contained enough to start from, but the PRD and TRD in `docs/` remain the source of truth. Agents read them and never edit them.

## Order and dependencies

```
00 Scaffold follow-ups   (you, small, can run any time)
01 SurgeCore contract    BLOCKING. Tag core-v1 when merged.
        |
        +-- 02 SurgeIngestTailer   \
        +-- 03 SurgeIngestProxy     |  parallel, start after core-v1
        +-- 04 SurgeWallets         |
        +-- 05 SurgeUI             /
        +-- 06 SurgeStateStore     can start once the three protocols in 01 are frozen
                |
                +-- 07 Menu bar app   needs 06 + 05
                +-- 08 Widget         needs only 01 + 05 and the SurgeSnapshot shape
                        |
                        09 Polish (up to three agents)
                        10 Integration hardening and QA
                        11 Packaging
```

## Rules every agent follows

- Read `AGENTS.md` and `README.md` first, then the PRD and TRD sections named in the task.
- `docs/` is read-only. If the documents are unclear or disagree, stop and ask the user. The questions each task already knows about are listed under "Ask the user before deciding".
- One task, one package, one branch named `feat/<package-name>`. Touch only that package and its tests. Frozen APIs are additive only.
- Tests cover business logic through public behaviour, not code structure. Lint and the package tests pass before the work is called done.
- Commit only when the user asks. Commit messages are short plain English with no co-author lines.

## Decisions already made

- The PRD v1.0 wins on every conflict with the design file or the TRD. The design file in `docs/` is v0.2 and is the only design reference. It matches the PRD on scope: read-only, no budget, no overall balance, one widget in three sizes, dark cards in both appearances, provider hues lime, green, magenta and violet.
- Menu bar readout: use the short text readout from the PRD (for example "1 Orch, 2 Workers, $1.42"). The design file says one number only. The PRD applies.
- No Nudge Agent button or any action on an agent anywhere.
- Development is local until the MVP. No Apple ID and no signing. The widget already shows in the gallery with the default "Sign to Run Locally" setting. App Group and Developer ID work wait until signing exists.
- Typeface: Beausite Classic is unlicensed, so the app and the widget ship Geist, named by `SurgeTypography.sansFamilyName` in `SurgeCore` and described in `README.md`. Fonts and colours come from `SurgeCore` tokens so the Beausite swap later is one change.
