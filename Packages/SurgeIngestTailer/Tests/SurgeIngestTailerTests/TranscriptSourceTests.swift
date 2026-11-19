import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestTailer

/// A source that only reports which workspace a session belongs to, so there is nothing to publish.
private struct MetadataOnlyAdapter: TranscriptSourceAdapter {
    let root: URL

    var info: TranscriptSourceInfo {
        TranscriptSourceInfo(
            kind: .piAgent,
            provider: "pi",
            displayName: "pi",
            root: root,
            capabilities: SourceCapabilities(
                transport: .appendOnlyJSONLFile,
                checkpoint: .byteOffset,
                providesUsage: false,
                providesCost: false,
                providesCompactionMarkers: false,
                providesParentSessionLink: false
            )
        )
    }

    func discover(now: Date) -> [SourceFile] {
        SourceScanner(root: root, now: { now }, identity: SourceLayout.pi).discover()
    }

    func makeReader() -> any TranscriptFileReader {
        MetadataOnlyReader()
    }
}

private struct MetadataOnlyReader: TranscriptFileReader {
    func ingest(line: Data, at date: Date) -> SourceEntry {
        SourceEntry(projectPath: "/Users/dev/workspace")
    }
}

@Test func everySourceDeclaresWhatItCanSupply() {
    let tailer = TranscriptTailer()
    let sources = tailer.sources
    #expect(sources.map(\.kind) == [.claudeCode, .piAgent])
    #expect(sources.map(\.provider) == ["anthropic", ""])

    let claude = sources[0].capabilities
    #expect(claude.transport == .appendOnlyJSONLFile)
    #expect(claude.checkpoint == .byteOffset)
    #expect(claude.providesUsage)
    // The Claude transcript has no billed amount, so no provider cost is claimed.
    #expect(claude.providesCost == false)
    #expect(claude.providesParentSessionLink)
    #expect(claude.providesCompactionMarkers == false)

    let piCapabilities = sources[1].capabilities
    #expect(piCapabilities.transport == .appendOnlyJSONLFile)
    #expect(piCapabilities.checkpoint == .byteOffset)
    #expect(piCapabilities.providesUsage)
    #expect(piCapabilities.providesCost)
    #expect(piCapabilities.providesParentSessionLink == false)
    #expect(piCapabilities.providesCompactionMarkers == false)
}

@Test func claudeCostsAreReportedAsLocalEstimates() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.sessionURL(session: "session-1")
    try fixture.append(
        try TranscriptFixtures.turn(
            TurnFixture(model: "claude-sonnet-5-5", input: 1_000, output: 500, cacheRead: 200)
        ) + "\n",
        to: url
    )

    let tailer = TranscriptTailer(
        sources: [.claudeCode(root: fixture.root)],
        clock: { fixture.clock.now() }
    )
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()
    _ = await recorder.wait(forCount: 2)

    let cost = try #require(await tailer.cost(forSession: "session-1"))
    #expect(cost.providerReportedUSD == nil)
    let estimate = try #require(cost.locallyEstimatedUSD)
    // 1_000 x $2/M + 500 x $10/M + 200 x $0.10/M
    #expect(abs(estimate - 0.00702) < 0.0000001)
    #expect(cost.provenance == .locallyEstimated)
    #expect(cost.unavailableTurnCount == 0)
    #expect(await tailer.capabilities(forSession: "session-1")?.providesCost == false)
    await tailer.shutdown()
}

@Test func aSourceWithoutUsagePublishesNoTurns() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: "pi-session")
    try fixture.append(
        try PiSessionFixtures.header() + "\n" + PiSessionFixtures.turn(PiTurnFixture(input: 10, output: 2))
            + "\n",
        to: url
    )

    let tailer = TranscriptTailer(
        adapters: [MetadataOnlyAdapter(root: fixture.piRoot)],
        clock: { fixture.clock.now() }
    )
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 1, timeout: .milliseconds(200))
    #expect(events.isEmpty)
    // The file is still tracked and its bytes consumed, so the next write is read from the offset.
    let checkpoints = await tailer.checkpoints()
    #expect(checkpoints.map { ($0.path as NSString).lastPathComponent } == [url.lastPathComponent])
    #expect((checkpoints.first?.offset ?? 0) > 0)
    #expect(await tailer.capabilities(forSession: "pi-session")?.providesUsage == false)
    await tailer.shutdown()
}
