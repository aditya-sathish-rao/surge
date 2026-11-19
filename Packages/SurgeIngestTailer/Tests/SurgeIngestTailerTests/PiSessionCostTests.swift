import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestTailer

@Test func piNamesTheProviderThatBillsTheTurnNotItself() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.turn(
            PiTurnFixture(model: "deepseek-flash", provider: "deepseek", input: 100, output: 20)
        ),
    ].joined(separator: "\n")
    try fixture.append(content + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 2)
    let descriptor = try #require(appeared(in: events).first)
    // The payer is the family that billed it. "pi" is the harness, and it stays in its own field.
    #expect(descriptor.provider == "deepseek")
    #expect(descriptor.harness?.kind == .piAgent)
    await tailer.shutdown()
}

@Test func piCarriesItsPerTurnCostToTheTurnEvent() async throws {
    let fixture = try TailerFixture()
    defer { fixture.remove() }
    let url = fixture.piSessionURL(session: piSession)
    let content = try [
        PiSessionFixtures.header(),
        PiSessionFixtures.turn(
            PiTurnFixture(
                model: "deepseek-flash",
                provider: "deepseek",
                input: 100,
                output: 20,
                costTotal: 0.0014
            )
        ),
        PiSessionFixtures.turn(
            PiTurnFixture(
                model: "deepseek-flash",
                provider: "deepseek",
                input: 50,
                output: 10,
                costTotal: 0.0007,
                totalFromProvider: true,
                timestamp: PiSessionFixtures.secondTimestamp
            )
        ),
    ].joined(separator: "\n")
    try fixture.append(content + "\n", to: url)

    let tailer = makePiTailer(fixture)
    let recorder = EventRecorder(tailer.events())
    await tailer.refresh()

    let events = await recorder.wait(forCount: 3)
    let turns = turns(in: events)
    // pi's own figure is the harness's number. `totalFromProvider` marks the provider's own bill.
    #expect(turns.first?.turnHarnessReportedUSD == 0.0014)
    #expect(turns.first?.turnProviderReportedUSD == nil)
    #expect(turns.first?.harnessReportedCostUSD == nil)
    #expect(turns.last?.turnProviderReportedUSD == 0.0007)
    #expect(turns.last?.turnHarnessReportedUSD == nil)
    await tailer.shutdown()
}
