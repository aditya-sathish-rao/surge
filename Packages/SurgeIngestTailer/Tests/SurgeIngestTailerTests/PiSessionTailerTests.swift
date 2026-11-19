import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestTailer

func makePiTailer(
    _ fixture: TailerFixture,
    checkpoints: [TailerCheckpoint] = []
) -> TranscriptTailer {
    TranscriptTailer(
        sources: [.pi(root: fixture.piRoot)],
        checkpoints: checkpoints,
        clock: { fixture.clock.now() }
    )
}

let piSession = "pi-session"

@Test func piResumesFromSavedOffsetWithNoDuplicateTurns() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let opening = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.turn(PiTurnFixture(input: 10, output: 2)),
        PiSessionFixtures.turn(
            PiTurnFixture(input: 20, output: 4, timestamp: PiSessionFixtures.secondTimestamp)
        ),
    ].joined(separator: "\n")
    try fixture.append(opening + "\n", to: url)

    let first = makePiTailer(fixture)
    let firstRecorder = EventRecorder(first.events())
    await first.refresh()
    let initial = await firstRecorder.wait(forCount: 3)
    #expect(appeared(in: initial).map(\.id) == [piSession])
    #expect(turns(in: initial).map(\.inputTokens) == [10, 20])
    let checkpoints = await first.checkpoints()
    await first.shutdown()

    try fixture.append(
        try PiSessionFixtures.turn(
            PiTurnFixture(input: 30, output: 6, timestamp: "2026-11-18T10:00:10.000Z")
        ) + "\n",
        to: url
    )

    let second = makePiTailer(fixture, checkpoints: checkpoints)
    let secondRecorder = EventRecorder(second.events())
    await second.refresh()
    let resumed = await secondRecorder.wait(forCount: 2)
    #expect(turns(in: resumed).map(\.inputTokens) == [30])
    await second.shutdown()
}

@Test func piLineSplitAcrossTwoWritesIsHeldUntilComplete() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let line = try PiSessionFixtures.turn(PiTurnFixture(input: 12, output: 3, cacheRead: 400)) + "\n"
    let splitIndex = line.index(line.startIndex, offsetBy: line.count / 2)

    try fixture.append(String(line[..<splitIndex]), to: url)
    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    let whileIncomplete = await recorder.wait(forCount: 1, timeout: .milliseconds(200))
    #expect(whileIncomplete.isEmpty)

    try fixture.append(String(line[splitIndex...]), to: url)
    await tailer.refresh()

    let events = await recorder.wait(forCount: 2)
    let turns = turns(in: events)
    #expect(turns.count == 1)
    #expect(turns.first?.inputTokens == 12)
    #expect(turns.first?.cacheHitTokens == 400)
    await tailer.shutdown()
}

@Test func piMalformedLinesAreSkippedWithoutLosingFollowingLines() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = try [
        "this is not json",
        PiSessionFixtures.turn(PiTurnFixture(input: 7, output: 1)),
        "{\"type\":\"message\",\"message\":",
        PiSessionFixtures.customMessage(content: "injected context"),
        PiSessionFixtures.turn(PiTurnFixture(input: 9, output: 2)),
    ].joined(separator: "\n")
    try fixture.append(content + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 3)
    #expect(turns(in: events).map(\.inputTokens) == [7, 9])
    await tailer.shutdown()
}

@Test func piUsageMapsWithAndWithoutCache() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let withCache = try PiSessionFixtures.turn(
        PiTurnFixture(
            input: 100,
            output: 40,
            cacheRead: 900,
            cacheWrite: 300,
            costTotal: 0.5,
            totalFromProvider: true
        )
    )
    let withoutCache = try PiSessionFixtures.turn(
        PiTurnFixture(
            input: 50,
            output: 10,
            timestamp: PiSessionFixtures.secondTimestamp
        )
    )
    let opening = try [PiSessionFixtures.header(), withCache, withoutCache].joined(separator: "\n")
    try fixture.append(opening + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 3)
    let turns = turns(in: events)
    #expect(turns.count == 2)
    #expect(turns.first?.inputTokens == 100)
    #expect(turns.first?.outputTokens == 40)
    #expect(turns.first?.cacheHitTokens == 900)
    // pi's input is uncached, so the prompt footprint adds both cache directions.
    #expect(turns.first?.currentContextTokens == 1_300)
    #expect(turns.first?.occurredAt == TranscriptFixtures.firstTimestamp)
    #expect(turns.last?.cacheHitTokens == 0)
    #expect(turns.last?.currentContextTokens == 50)

    let descriptor = try #require(appeared(in: events).first)
    #expect(descriptor.id == piSession)
    #expect(descriptor.provider == "anthropic")
    #expect(descriptor.modelName == "claude-sonnet-5-5")
    #expect(descriptor.maxContextWindow == 200_000)
    #expect(descriptor.projectPath == "/Users/dev/workspace")
    #expect(descriptor.occurredAt == TranscriptFixtures.firstTimestamp)
    await tailer.shutdown()
}

@Test func piModelChangeResolvesTheModelForFollowingTurns() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.turn(PiTurnFixture(model: "claude-sonnet-5-5", input: 10)),
        // A turn whose message names no model takes the model from the last model_change.
        PiSessionFixtures.modelChange("deepseek-chat"),
        PiSessionFixtures.turn(PiTurnFixture(model: nil, input: 20)),
        // A message that names its own model wins for that turn.
        PiSessionFixtures.turn(PiTurnFixture(model: "claude-sonnet", input: 30)),
    ].joined(separator: "\n")
    try fixture.append(content + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 4)
    #expect(turns(in: events).map(\.modelName) == ["claude-sonnet-5-5", "deepseek-chat", "claude-sonnet"])
    await tailer.shutdown()
}

@Test func piNonTurnRecordsAreMetadataNeverTurns() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.thinkingLevelChange(),
        PiSessionFixtures.custom(),
        PiSessionFixtures.customMessage(content: "injected context"),
        PiSessionFixtures.compaction(),
        PiSessionFixtures.usageEntry(),
        PiSessionFixtures.modelChange("claude-sonnet"),
        PiSessionFixtures.turn(PiTurnFixture(input: 11, output: 4, costTotal: 0.25, totalFromProvider: true)),
    ].joined(separator: "\n")
    try fixture.append(content + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    // One session appearance and one turn: every metadata record emitted nothing.
    let events = await recorder.wait(forCount: 2)
    #expect(turns(in: events).map(\.inputTokens) == [11])
    #expect(appeared(in: events).count == 1)
    // The cache-warm usage record's cost is not a turn, so it is not counted here.
    #expect(await tailer.cost(forSession: piSession)?.providerReportedUSD == 0.25)
    await tailer.shutdown()
}

@Test func piTruncatedFileResetsTheOffsetAndReadsTheNewContent() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let firstTurn = try PiSessionFixtures.turn(PiTurnFixture(input: 10, output: 2))
    let secondTurn = try PiSessionFixtures.turn(
        PiTurnFixture(input: 20, output: 4, timestamp: PiSessionFixtures.secondTimestamp)
    )
    try fixture.append(firstTurn + "\n" + secondTurn + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    let initial = await recorder.wait(forCount: 3)
    #expect(turns(in: initial).map(\.inputTokens) == [10, 20])

    try fixture.truncate(to: try PiSessionFixtures.turn(PiTurnFixture(input: 77, output: 8)) + "\n", at: url)
    await tailer.refresh()

    let events = await recorder.wait(forCount: 4)
    #expect(turns(in: events).map(\.inputTokens) == [10, 20, 77])
    await tailer.shutdown()
}

@Test func piReportsNoParentSessionLinkRatherThanInferringOne() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.turn(PiTurnFixture(input: 5, output: 1)),
    ].joined(separator: "\n")
    try fixture.append(content + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    _ = await recorder.wait(forCount: 2)

    #expect(await tailer.parentSessionID(forSession: piSession) == nil)
    let capabilities = try #require(await tailer.capabilities(forSession: piSession))
    #expect(capabilities.providesParentSessionLink == false)
    #expect(capabilities.transport == .appendOnlyJSONLFile)
    #expect(capabilities.checkpoint == .byteOffset)
    await tailer.shutdown()
}

@Test func piCostsKeepBilledAndEstimatedAmountsApart() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    try fixture.append(
        try [
            PiSessionFixtures.header(),
            PiSessionFixtures.turn(PiTurnFixture(input: 10, output: 2, costTotal: 0.5, totalFromProvider: true)),
            PiSessionFixtures.turn(
                PiTurnFixture(
                    input: 10,
                    output: 2,
                    costTotal: 0.25,
                    totalFromProvider: false,
                    timestamp: PiSessionFixtures.secondTimestamp
                )
            ),
            // Not in the pricing table and no cost object: the cost is unavailable, never zero.
            PiSessionFixtures.turn(PiTurnFixture(model: "gpt-5", input: 10, output: 2)),
        ].joined(separator: "\n") + "\n",
        to: url
    )

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    _ = await recorder.wait(forCount: 4)

    let cost = try #require(await tailer.cost(forSession: piSession))
    #expect(cost.provider == "anthropic")
    #expect(cost.providerReportedUSD == 0.5)
    // pi's own figure for a turn is the harness's number, not a local estimate.
    #expect(cost.harnessReportedUSD == 0.25)
    #expect(cost.locallyEstimatedUSD == nil)
    #expect(cost.unavailableTurnCount == 1)
    #expect(cost.provenance == .mixed)
    await tailer.shutdown()
}

@Test func piTranscriptContentCanNotReachATurnRecord() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = "SECRET_PROMPT_TEXT"
    let lines = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.turn(
            PiTurnFixture(input: 10, output: 2, costTotal: 0.5, totalFromProvider: true, content: content)
        ),
        PiSessionFixtures.customMessage(content: content),
    ].joined(separator: "\n")
    try fixture.append(lines + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 2)
    #expect(turns(in: events).count == 1)
    #expect(String(describing: events).contains(content) == false)
    await tailer.shutdown()
}

@Test func piIncompleteUsageIsNotPublishedAsATurn() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    // A turn without the cache counts is incomplete. Publishing it would report them as zero.
    let incomplete =
        #"{"type":"message","id":"a1","parentId":null,"timestamp":"2026-11-18T10:00:00.000Z","#
        + #""message":{"role":"assistant","model":"claude-sonnet-5-5","usage":{"input":10,"output":2}}}"#
    let complete = try PiSessionFixtures.turn(PiTurnFixture(input: 20, output: 4))
    try fixture.append([incomplete, complete].joined(separator: "\n") + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 2)
    #expect(turns(in: events).map(\.inputTokens) == [20])
    #expect(await tailer.cost(forSession: piSession)?.unavailableTurnCount == 0)
    await tailer.shutdown()
}
