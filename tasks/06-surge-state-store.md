# 06 - SurgeStateStore

Phase 3. One agent. Can start once the three protocols are frozen in task 01, without waiting for the pipelines. Owns `Packages/SurgeStateStore` only. Branch: `feat/surge-state-store`.

Read: PRD sections 6, 6.2, 8. TRD sections 4, 10, 13.

## Goal

The single actor that owns the canonical `WorkspaceSession` tree and merges all three pipelines. Every UI surface reads from it.

## Key requirements (TRD 10)

- One `actor`. It is the only place the tree is mutated. No manual locks anywhere.
- Each pipeline runs in its own `Task` consuming its own `AsyncStream` and calls the actor's async `apply(_:)` methods.
- Derived state is computed inside the actor on every merge, never in the UI:
  - **Stall detection**: compare `lastTokenAt` with the model's `stallThresholdSeconds` (default 120 s, 300 s for `deepseek-reasoner`). Stalled only when not waiting for you.
  - **Sort order** (PRD 6.2): workspaces needing attention first, then by spend. Within a workspace, agents needing attention first, each agent's sub-agents directly after it.
  - **Cost totals** per workspace.
  - Done agents stay visible for 10 minutes.
- A sub-agent's state never changes its parent's. A workspace header shows the attention symbol and a count if anything inside needs you.
- Expose the tree to SwiftUI as an `@Observable` snapshot type so only changed rows re-render.
- Take the clock as an injected dependency.
- The snapshot-writing and widget-reload policy does not live here. It lives in the app target (task 07).
- Depend on `SurgeCore` protocols only. Inject real pipelines later with no code change here.

## Business logic to test (synthetic `AsyncStream`s, injected clock)

- Merging events from all three pipelines, including deliberately interleaved and racy input, gives the same tree regardless of order where it should
- A worker request from the proxy nests under the right workspace and orchestrator
- Stall flips exactly when the threshold passes, uses the per-model threshold, and never applies to an agent waiting for you
- Sort order for the cases in PRD 6.2, including ties
- Workspace cost totals and attention counts
- Done expiry after 10 minutes
- Balance low and empty modifiers from the configured thresholds

## Ask the user before deciding

- Behaviour when two top-level agents (peers) share a workspace and a worker request arrives.
- How "Pause Monitoring" is represented (state store flag, or the app simply stops feeding it).

## Definition of done

Store works against fake pipelines, tests and lint pass, nothing outside the package touched.
