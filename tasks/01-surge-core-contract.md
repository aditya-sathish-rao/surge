# 01 - SurgeCore contract freeze

Phase 1. One agent, blocking. Everything else depends on this. Owns `Packages/SurgeCore` only. Branch: `feat/surge-core`. Finish by tagging `core-v1`.

Read: PRD sections 5, 6, 9. TRD sections 4, 5, 15 (Phase 1), 17.1. Design file sections "Color", "Status system", "SwiftUI mapping".

## Deliverables

1. `WorkspaceSession`, `AgentNode`, `AgentStatus`, `Provider`
2. `SurgeSnapshot` and its parts (`AccountBalance`, `DailySpendPoint`)
3. The three pipeline protocols: `SessionTailing`, `WorkerTraffic`, `WalletPolling`, and their event types
4. Design tokens: colours, fonts, spacing, sizes
5. `models-pricing.json` schema, loader and cost and context maths
6. Formatting utilities
7. Sample fixtures that every other package tests against
8. Tag `core-v1`

## Key snippets

Data model (TRD 5, exact shape from the blueprint):

```swift
struct WorkspaceSession: Identifiable, Codable {
    let id: UUID
    let projectPath: String
    var orchestrator: AgentNode          // e.g., Claude Sonnet (local JSONL)
    var workers: [AgentNode]             // e.g., DeepSeek-V3 / R1 via proxy
    var totalTreeCostUSD: Double {
        orchestrator.estimatedCostUSD + workers.reduce(0) { $0 + $1.estimatedCostUSD }
    }
}

struct AgentNode: Identifiable, Codable {
    let id: String                        // session ID, or worker PID/trace ID
    let provider: String                  // "anthropic", "deepseek", "openrouter"
    let modelName: String
    var status: AgentStatus
    var inputTokens: Int
    var outputTokens: Int
    var cacheHitTokens: Int
    var currentContextTokens: Int         // prompt tokens from latest turn
    var maxContextWindow: Int
    var estimatedCostUSD: Double
    var lastTokenAt: Date                 // drives stall detection
    var contextUsageRatio: Double {
        guard maxContextWindow > 0 else { return 0 }
        return min(Double(currentContextTokens) / Double(maxContextWindow), 1.0)
    }
}
```

Snapshot the widget reads (TRD 5.2). Must be small, flattened and versioned. The widget never imports the state store:

```swift
struct SurgeSnapshot: Codable {
    let generatedAt: Date
    let workspaces: [WorkspaceSession]     // already sorted per PRD 6.2
    let balances: [AccountBalance]
    let dailySpend: [DailySpendPoint]      // last 7 days
}
```

Status presentation, one source of truth for every surface (design file):

```swift
enum AgentStatus { case working, waitingForYou, stalled(since: Date), compacting, idle(since: Date), done, noSignal }
// symbols: bolt.fill, hand.raised.fill, exclamationmark.triangle.fill,
// arrow.down.and.line.horizontal.and.arrow.up, pause.fill, checkmark, bolt.slash
// needsYou: true for .stalled and .waitingForYou
```

Pricing table (TRD 17.1). Add `stallThresholdSeconds`, which the blueprint lacked:

```json
{ "deepseek-reasoner": { "contextWindow": 128000, "inputPerMillion": 0.55, "outputPerMillion": 2.19,
                         "cacheReadPerMillion": 0.14, "stallThresholdSeconds": 300 } }
```

Protocol shapes (a sketch, design the final form). Each yields an `AsyncStream` of immutable events and the consumer only ever sees the protocol:

```swift
protocol SessionTailing: Sendable { func events() -> AsyncStream<TailerEvent> }   // appeared, turn appended, ended
protocol WorkerTraffic:  Sendable { func events() -> AsyncStream<ProxyEvent> }
protocol WalletPolling:  Sendable { func updates() -> AsyncStream<BalanceUpdate> }
```

Thresholds to encode as named constants: context high 70 percent, near limit 90 percent; stall default 120 s; low balance under $5, empty under $0.50; Done shown 10 minutes; snapshot stale after 5 minutes.

## Business logic to test

- Cost from token counts and the pricing table, including cache read pricing
- `contextUsageRatio` clamping and the zero-window case
- Pricing table decoding, unknown model handling, per-model stall threshold
- Status mapping and `needsYou`
- Threshold functions: ratio to normal, high or near limit; balance to normal, low or empty
- `SurgeSnapshot` encode and decode round trip

## Ask the user before deciding

- Nothing on colours or typeface. Both are decided: take the palette and rules from the design file (Color and Type sections). Reference study values: lime #DFE301, green #03C37B, magenta #FF79FB, violet #A86BD6 identify providers, and orange #FFAA4F and coral #FF7D6B are status only. Use Geist now, with Fira Code as the mono face. Tokens make the Beausite swap one change.
- Which Claude models go in the real pricing table beyond the three examples in the TRD, and their prices.
- Whether `provider` stays a `String` as in the blueprint or becomes the `Provider` enum the TRD also names.

## Definition of done

Package builds with Swift 6 strict concurrency, tests and lint pass, fixtures are usable by every other package, tag `core-v1` pushed. Tell the user so the four parallel streams can start.
