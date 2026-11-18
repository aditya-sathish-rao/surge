import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestProxy

@Test func ancestryFollowsParentProcesses() {
    let lookup = FakeProcessLookup(
        clientPID: 300,
        factsByPID: [
            300: ProcessFacts(processID: 300, parentProcessID: 200, workingDirectory: "/tmp/work"),
            200: ProcessFacts(processID: 200, parentProcessID: 100, workingDirectory: "/tmp/work"),
            100: ProcessFacts(processID: 100, parentProcessID: 1, workingDirectory: "/tmp/work"),
        ]
    )
    let ancestry = WorkerAttribution.ancestry(startingAt: 300, using: lookup)
    #expect(ancestry == [300, 200, 100])
}

@Test func exactlyOneAncestorOrchestratorWins() {
    let sessions = [
        OrchestratorSession(sessionID: "a", processID: 200),
        OrchestratorSession(sessionID: "b", processID: 999),
    ]
    #expect(
        WorkerAttribution.parentSessionID(ancestors: [300, 200, 100], orchestrators: sessions) == "a"
    )
}

@Test func twoAncestorOrchestratorsAreAmbiguous() {
    let sessions = [
        OrchestratorSession(sessionID: "a", processID: 200),
        OrchestratorSession(sessionID: "b", processID: 100),
    ]
    #expect(WorkerAttribution.parentSessionID(ancestors: [300, 200, 100], orchestrators: sessions) == nil)
}

@Test func noAncestorOrchestratorLeavesTheWorkerUnattributed() {
    let sessions = [OrchestratorSession(sessionID: "a", processID: 999)]
    #expect(WorkerAttribution.parentSessionID(ancestors: [300, 200], orchestrators: sessions) == nil)
}

@Test func routeMatchingRequiresAPathSegmentBoundary() {
    let route = ProxyRoute(prefix: "deepseek", upstream: URL(fileURLWithPath: "/tmp/deepseek"))
    let configuration = ProxyConfiguration(port: 0, routes: [route])

    #expect(configuration.route(forPath: "/deepseek/chat")?.path == "/chat")
    #expect(configuration.route(forPath: "/deepseek")?.path == "/")
    #expect(configuration.route(forPath: "/deepseeker/chat") == nil)
}

@Test func unresolvableProcessYieldsAnEmptyWorkspace() {
    let attribution = WorkerAttribution(
        processLookup: FakeProcessLookup(clientPID: nil),
        orchestratorLookup: EmptyOrchestratorLookup()
    )
    let result = attribution.attribute(sourcePort: 1, destinationPort: 8_899)
    #expect(result.processID == nil)
    #expect(result.projectPath.isEmpty)
    #expect(result.parentSessionID == nil)
}

@Test func defaultsMatchTheWorkerRoutingContract() {
    let configuration = ProxyConfiguration.default
    #expect(configuration.host == "127.0.0.1")
    #expect(configuration.port == 8_899)

    let deepseek = configuration.routes.first { $0.prefix == "deepseek" }
    #expect(deepseek?.upstream.absoluteString == "https://api.deepseek.com")

    let openrouter = configuration.routes.first { $0.prefix == "openrouter" }
    #expect(openrouter?.upstream.absoluteString == "https://openrouter.ai/api/v1")
}
