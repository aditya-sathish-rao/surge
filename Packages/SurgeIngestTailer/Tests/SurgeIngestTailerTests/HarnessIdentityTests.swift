import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestTailer

@Suite("Harness identity and de-duplication")
struct HarnessIdentityTests {
    @Test func aClaudeSessionCarriesItsHarnessIdentity() async throws {
        let fixture = try TailerFixture()
        defer { fixture.remove() }
        let url = fixture.sessionURL(session: "session-1")
        try fixture.append(
            try TranscriptFixtures.turn(
                TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 200, version: "2.0.31")
            ) + "\n",
            to: url
        )

        let tailer = TranscriptTailer(sources: [.claudeCode(root: fixture.root)], clock: { fixture.clock.now() })
        let recorder = EventRecorder(tailer.events())
        defer { Task { await tailer.shutdown() } }
        await tailer.refresh()
        _ = await recorder.wait(forCount: 1)

        let descriptor = try #require(appeared(in: recorder.recordedEvents()).first)
        let harness = try #require(descriptor.harness)
        #expect(harness.kind == .claudeCode)
        #expect(harness.transport == .jsonl)
        #expect(harness.sessionID == "session-1")
        #expect(harness.version == "2.0.31")
        #expect(descriptor.parentSessionID == nil)
    }

    @Test func aSessionThatNamesAParentKeepsIt() async throws {
        let fixture = try TailerFixture()
        defer { fixture.remove() }
        let parent = fixture.sessionURL(session: "parent-1")
        let child = fixture.subagentURL(agent: "a1", parent: "parent-1")
        let turn =
            try TranscriptFixtures.turn(
                TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 200, uuid: "turn-1")
            ) + "\n"
        try fixture.append(turn, to: parent)
        try fixture.append(turn, to: child)

        let tailer = TranscriptTailer(sources: [.claudeCode(root: fixture.root)], clock: { fixture.clock.now() })
        let recorder = EventRecorder(tailer.events())
        defer { Task { await tailer.shutdown() } }
        await tailer.refresh()
        _ = await recorder.wait(forCount: 2)

        let childDescriptor = try #require(
            appeared(in: recorder.recordedEvents()).first { $0.id == "agent-a1" }
        )
        #expect(childDescriptor.parentSessionID == "parent-1")
        #expect(childDescriptor.harness?.kind == .claudeCode)
    }

    @Test func aSidechainTurnFindsItsParentThroughTheTurnItNames() async throws {
        let fixture = try TailerFixture()
        defer { fixture.remove() }
        let parent = fixture.sessionURL(session: "parent-1", project: "project-zeta")
        let sidechain = fixture.sessionURL(session: "side-1", project: "project-alpha")
        try fixture.append(
            try TranscriptFixtures.turn(
                TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 200, uuid: "parent-turn")
            ) + "\n",
            to: parent
        )
        try fixture.append(
            try TranscriptFixtures.turn(
                TurnFixture(
                    model: "claude-sonnet-5-5",
                    input: 400,
                    output: 100,
                    uuid: "side-turn",
                    parentUuid: "parent-turn",
                    isSidechain: true
                )
            ) + "\n",
            to: sidechain
        )

        let tailer = TranscriptTailer(sources: [.claudeCode(root: fixture.root)], clock: { fixture.clock.now() })
        let recorder = EventRecorder(tailer.events())
        defer { Task { await tailer.shutdown() } }
        await tailer.refresh()
        _ = await recorder.wait(forCount: 3)

        let sideDescriptors = appeared(in: recorder.recordedEvents()).filter { $0.id == "side-1" }
        #expect(try #require(sideDescriptors.last).parentSessionID == "parent-1")
    }

    @Test func aRepeatedRecordIsCountedOnce() async throws {
        let fixture = try TailerFixture()
        defer { fixture.remove() }
        let url = fixture.sessionURL(session: "session-1")
        let line =
            try TranscriptFixtures.turn(
                TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 200, uuid: "same-turn")
            ) + "\n"
        try fixture.append(line + line, to: url)

        let tailer = TranscriptTailer(sources: [.claudeCode(root: fixture.root)], clock: { fixture.clock.now() })
        let recorder = EventRecorder(tailer.events())
        defer { Task { await tailer.shutdown() } }
        await tailer.refresh()
        _ = await recorder.wait(forCount: 2)

        let recorded = turns(in: recorder.recordedEvents())
        #expect(recorded.count == 1)
        #expect(recorded.first?.eventID == "same-turn")
        #expect(recorded.first?.inputTokens == 1_000)
        // The cost summary counts the turn once too.
        let cost = try #require(await tailer.cost(forSession: "session-1"))
        #expect(cost.locallyEstimatedUSD != nil)
    }

    @Test func theHarnessRunningCostTravelsWithTheNextTurn() async throws {
        let fixture = try TailerFixture()
        defer { fixture.remove() }
        let url = fixture.sessionURL(session: "session-1")
        try fixture.append(
            try TranscriptFixtures.turn(
                TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 200, uuid: "turn-1")
            ) + "\n"
                + TranscriptFixtures.costState(session: "session-1", totalCostUSD: 0.0524) + "\n"
                + TranscriptFixtures.turn(
                    TurnFixture(model: "claude-sonnet-5-5", input: 10, output: 5, uuid: "turn-2")
                ) + "\n",
            to: url
        )

        let tailer = TranscriptTailer(sources: [.claudeCode(root: fixture.root)], clock: { fixture.clock.now() })
        let recorder = EventRecorder(tailer.events())
        defer { Task { await tailer.shutdown() } }
        await tailer.refresh()
        _ = await recorder.wait(forCount: 3)

        let recorded = turns(in: recorder.recordedEvents())
        #expect(recorded.first?.harnessReportedCostUSD == nil)
        #expect(abs((recorded.last?.harnessReportedCostUSD ?? 0) - 0.0524) < 0.000_001)
        // The session summary carries the harness total as its own provenance, never mixed into
        // the locally estimated sum.
        let cost = try #require(await tailer.cost(forSession: "session-1"))
        #expect(abs((cost.harnessReportedUSD ?? 0) - 0.0524) < 0.000_001)
        #expect(cost.provenance == .mixed)
    }

    @Test func aHarnessTotalItCouldNotPriceIsNotReported() async throws {
        let fixture = try TailerFixture()
        defer { fixture.remove() }
        let url = fixture.sessionURL(session: "session-1")
        try fixture.append(
            TranscriptFixtures.costState(session: "session-1", totalCostUSD: 9.99, hasUnknownModelCost: true) + "\n"
                + TranscriptFixtures.turn(
                    TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 200, uuid: "turn-1")
                ) + "\n",
            to: url
        )

        let tailer = TranscriptTailer(sources: [.claudeCode(root: fixture.root)], clock: { fixture.clock.now() })
        let recorder = EventRecorder(tailer.events())
        defer { Task { await tailer.shutdown() } }
        await tailer.refresh()
        _ = await recorder.wait(forCount: 1)

        #expect(turns(in: recorder.recordedEvents()).first?.harnessReportedCostUSD == nil)
    }
}
