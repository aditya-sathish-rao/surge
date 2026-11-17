# 02 - SurgeIngestTailer (Pipeline A)

Phase 2A. Starts after `core-v1`. Owns `Packages/SurgeIngestTailer` only. Branch: `feat/surge-ingest-tailer`.

Read: PRD sections 5, 6.2, 11.1. TRD sections 4, 7, 13.

## Goal

Watch Claude Code transcripts and publish what happened as immutable events. Implement `SessionTailing` from SurgeCore. The tailer never knows the state store exists.

## Key requirements (TRD 7)

- Source: `~/.claude/projects/**/*.jsonl`
- Track the last-read **byte offset** per file. On a write notification, seek to that offset and decode only the new lines. Never re-read a whole file.
- Use `DispatchSource` to watch for writes.
- Per turn extract: `model`, `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`.
- Detect sub-agents by watching adjacent `subagents/` folders, for foreground and background tasks delegated by the main session.
- Emit events: session appeared, turn appended, session ended.
- A session should appear within 5 seconds of its first turn (PRD 11.1).

## Constraints

- Imports `SurgeCore` and Foundation only. No SwiftUI, no networking.
- Prompt and response text must never be stored, logged or published. Extract the numeric fields and metadata only.
- Read the working directory and session ID from the transcript so the state store can group by workspace.

## Business logic to test (fixture `.jsonl` files in a temp directory)

- Resuming from a saved byte offset yields only new turns, none twice
- A line split across two writes is held until complete, not dropped or half-parsed
- Malformed lines are skipped without losing following lines
- Token and cache fields map correctly for turns with and without cache use
- A new file appears as a new session; a `subagents/` entry appears as a sub-agent of the right parent
- A truncated or replaced file resets the offset safely

Do not read the developer's real `~/.claude` in tests.

## Ask the user before deciding

- How "waiting for you" and "compacting" are detected from the transcript. The TRD does not say, and the PRD lists both states.
- What counts as session ended (file idle for how long, or an explicit marker).

## Definition of done

`SessionTailing` implemented, fixtures and tests pass, no files touched outside the package, lint clean.
