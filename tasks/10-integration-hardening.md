# 10 - Integration hardening and end-to-end QA

Phase 6. A small pair of agents. Start after the pipelines, state store, app and widget are merged.

Read: PRD section 11.1 (definition of done). TRD sections 13, 15 (Phase 6), 16.

## Goal

Run the whole system for real and check it against the PRD definition of done. Bug fixes go back to the single package that owns the bug. Never patch a consuming package.

## Checks (PRD 11.1), run end to end

1. A real Claude Code session appears in the menu bar within 5 seconds of its first turn, with the right provider, model name and context percentage.
2. A DeepSeek or OpenRouter worker with its base URL pointed at `127.0.0.1:8899` appears as a sub-agent under the correct workspace within 5 seconds of its first request.
3. A stalled agent shows the hatched Fuse, symbol and word within one tick of crossing its threshold. No false positives from normal reasoning pauses (test with `deepseek-reasoner`).
4. Today's spend and both balances update on their own. No manual refresh exists anywhere in the UI.
5. Menu bar, popover, panel and the widget at all three sizes pass the accessibility floor: contrast, VoiceOver, Reduce Motion, Differentiate Without Color.
6. No prompt or response content is written to disk. Inspect `~/Library/Application Support/Surge/` and the App Group container and confirm only the persisted fields exist.

## Also verify

- The widget feels live within the refresh budget and says "Updated 2 min ago" when it is stale
- The proxy is unreachable from another machine on the network (bind check)
- Killing the proxy port or the transcripts shows "No signal" with a reason, not a crash
- Starting with no agents shows the empty state

## Ask the user before deciding

- Which real API keys and projects to use for the live run.

## Definition of done

Every check above passes or has a filed bug against its owning package. Write a short results note for the user, in plain English.
