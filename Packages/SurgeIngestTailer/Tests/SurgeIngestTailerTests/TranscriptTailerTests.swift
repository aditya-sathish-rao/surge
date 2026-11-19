import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestTailer

private func makeTailer(
    _ fixture: TailerFixture,
    checkpoints: [TailerCheckpoint] = []
) -> TranscriptTailer {
    TranscriptTailer(
        sources: [.claudeCode(root: fixture.root)],
        checkpoints: checkpoints,
        clock: { fixture.clock.now() }
    )
}

@Test func resumingFromSavedOffsetYieldsOnlyNewTurns() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let firstTurn = try TranscriptFixtures.turn(TurnFixture(input: 10, output: 2))
    let secondTurn = try TranscriptFixtures.turn(
        TurnFixture(input: 20, output: 4, timestamp: "2026-11-18T10:00:05.000Z")
    )
    try fixture.append(firstTurn + "\n" + secondTurn + "\n", to: url)

    let first = makeTailer(fixture)
    let firstRecorder = EventRecorder(first.events())
    await first.refresh()
    let initial = await firstRecorder.wait(forCount: 3)
    #expect(appeared(in: initial).map(\.id) == ["session-1"])
    #expect(turns(in: initial).map(\.inputTokens) == [10, 20])
    let checkpoints = await first.checkpoints()
    await first.shutdown()

    let thirdTurn = try TranscriptFixtures.turn(
        TurnFixture(input: 30, output: 6, timestamp: "2026-11-18T10:00:10.000Z")
    )
    try fixture.append(thirdTurn + "\n", to: url)

    let second = makeTailer(fixture, checkpoints: checkpoints)
    let secondRecorder = EventRecorder(second.events())
    await second.refresh()
    let resumed = await secondRecorder.wait(forCount: 2)
    #expect(turns(in: resumed).map(\.inputTokens) == [30])
    await second.shutdown()
}

@Test func lineSplitAcrossTwoWritesIsHeldUntilComplete() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let line = try TranscriptFixtures.turn(TurnFixture(input: 12, output: 3, cacheRead: 400)) + "\n"
    let splitIndex = line.index(line.startIndex, offsetBy: line.count / 2)

    try fixture.append(String(line[..<splitIndex]), to: url)
    let tailer = makeTailer(fixture)
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

@Test func malformedLinesAreSkippedWithoutLosingFollowingLines() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let firstTurn = try TranscriptFixtures.turn(TurnFixture(input: 7, output: 1))
    let secondTurn = try TranscriptFixtures.turn(
        TurnFixture(input: 9, output: 2, timestamp: "2026-11-18T10:00:05.000Z")
    )
    let notJSON = "this is not json"
    let truncatedJSON = "{\"type\":\"assistant\",\"message\":"
    let userLine = try TranscriptFixtures.metadataLine(type: "user", session: "session-1")
    let content =
        notJSON + "\n"
        + firstTurn + "\n"
        + truncatedJSON + "\n"
        + userLine + "\n"
        + secondTurn + "\n"
    try fixture.append(content, to: url)

    let tailer = makeTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 3)
    #expect(turns(in: events).map(\.inputTokens) == [7, 9])
    await tailer.shutdown()
}

@Test func tokenAndCacheFieldsMapToTurnAndDescriptor() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let withCache = try TranscriptFixtures.turn(
        TurnFixture(input: 100, output: 40, cacheRead: 900, cacheCreation: 300)
    )
    let withoutCache = try TranscriptFixtures.turn(
        TurnFixture(input: 50, output: 10, timestamp: "2026-11-18T10:00:05.000Z")
    )
    try fixture.append(withCache + "\n" + withoutCache + "\n", to: url)

    let tailer = makeTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 3)
    let turns = turns(in: events)
    #expect(turns.count == 2)
    #expect(turns.first?.inputTokens == 100)
    #expect(turns.first?.outputTokens == 40)
    #expect(turns.first?.cacheHitTokens == 900)
    #expect(turns.first?.currentContextTokens == 1_300)
    #expect(turns.first?.occurredAt == TranscriptFixtures.firstTimestamp)
    #expect(turns.last?.cacheHitTokens == 0)
    #expect(turns.last?.currentContextTokens == 50)

    let descriptor = try #require(appeared(in: events).first)
    #expect(descriptor.id == "session-1")
    #expect(descriptor.provider == "anthropic")
    #expect(descriptor.modelName == "claude-sonnet-5-5")
    #expect(descriptor.maxContextWindow == 200_000)
    #expect(descriptor.projectPath == "/Users/dev/workspace")
    #expect(descriptor.occurredAt == TranscriptFixtures.firstTimestamp)
    await tailer.shutdown()
}

@Test func subagentTranscriptAppearsAsAChildOfItsParentSession() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let parent = "11111111-1111-4111-8111-111111111111"
    let agent = "abc123"
    let parentTurn = try TranscriptFixtures.turn(TurnFixture(session: parent, input: 10, output: 2))
    let agentTurn = try TranscriptFixtures.turn(TurnFixture(session: parent, input: 4, output: 1))
    try fixture.append(parentTurn + "\n", to: fixture.sessionURL(session: parent))
    try fixture.append(
        agentTurn + "\n",
        to: fixture.subagentURL(agent: agent, parent: parent)
    )

    let tailer = makeTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 4)
    #expect(Set(appeared(in: events).map(\.id)) == [parent, "agent-\(agent)"])
    #expect(await tailer.parentSessionID(forSession: "agent-\(agent)") == parent)
    #expect(await tailer.parentSessionID(forSession: parent) == nil)
    await tailer.shutdown()
}

@Test func truncatedFileResetsTheOffsetAndReadsTheNewContent() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let firstTurn = try TranscriptFixtures.turn(TurnFixture(input: 10, output: 2))
    let secondTurn = try TranscriptFixtures.turn(
        TurnFixture(input: 20, output: 4, timestamp: "2026-11-18T10:00:05.000Z")
    )
    try fixture.append(firstTurn + "\n" + secondTurn + "\n", to: url)

    let tailer = makeTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    let initial = await recorder.wait(forCount: 3)
    #expect(turns(in: initial).map(\.inputTokens) == [10, 20])

    let rewritten = try TranscriptFixtures.turn(TurnFixture(input: 77, output: 8)) + "\n"
    try fixture.truncate(to: rewritten, at: url)
    await tailer.refresh()

    let events = await recorder.wait(forCount: 4)
    #expect(turns(in: events).map(\.inputTokens) == [10, 20, 77])
    await tailer.shutdown()
}

@Test func replacedFileResetsTheOffsetAndReadsTheNewContent() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let firstTurn = try TranscriptFixtures.turn(TurnFixture(input: 10, output: 2))
    let secondTurn = try TranscriptFixtures.turn(
        TurnFixture(input: 20, output: 4, timestamp: "2026-11-18T10:00:05.000Z")
    )
    try fixture.append(firstTurn + "\n" + secondTurn + "\n", to: url)

    let tailer = makeTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    let initial = await recorder.wait(forCount: 3)
    #expect(turns(in: initial).map(\.inputTokens) == [10, 20])

    let rewritten = try TranscriptFixtures.turn(TurnFixture(input: 55, output: 6)) + "\n"
    try fixture.replaceFile(at: url, with: rewritten)
    await tailer.refresh()

    let events = await recorder.wait(forCount: 4)
    #expect(turns(in: events).map(\.inputTokens) == [10, 20, 55])
    await tailer.shutdown()
}

@Test func sessionEndsAfterTenMinutesWithoutNewBytes() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    let tailer = makeTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    let line = try TranscriptFixtures.turn(TurnFixture(input: 5, output: 1)) + "\n"
    try fixture.append(line, to: url)
    await tailer.refresh()
    let started = await recorder.wait(forCount: 2)
    #expect(turns(in: started).count == 1)

    fixture.clock.advance(by: TailerDefaults.sessionEndedIdleSeconds - 1)
    await tailer.refresh()
    let beforeDeadline = await recorder.wait(forCount: 3, timeout: .milliseconds(200))
    #expect(ended(in: beforeDeadline).isEmpty)

    fixture.clock.advance(by: 2)
    let deadline = fixture.clock.now()
    await tailer.refresh()
    let afterDeadline = await recorder.wait(forCount: 3)
    #expect(ended(in: afterDeadline) == ["session-1"])
    // An end published before the deadline would carry the earlier time.
    if case .sessionEnded(_, let occurredAt) = afterDeadline.last {
        #expect(occurredAt == deadline)
    } else {
        Issue.record("expected the last event to be sessionEnded")
    }
    await tailer.shutdown()
}
