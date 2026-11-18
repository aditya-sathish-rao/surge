import Foundation
import Network
import SurgeCore
import Testing

@testable import SurgeIngestProxy

@Test func passesHeadersAndBodyThroughUnchanged() async throws {
    let requestBody = Data(
        #"{"model":"deepseek-chat","messages":[{"role":"user","content":"hello"}]}"#.utf8
    )
    let responseBody = Data(#"{"model":"deepseek-chat","choices":[{"message":{"content":"hi"}}]}"#.utf8)
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: responseBody
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: [
            "Authorization": "Bearer sk-worker-abc",
            "Content-Type": "application/json",
            "X-Worker": "alpha",
        ],
        body: requestBody
    )
    let received = try await ProxyTestSupport.exchange(port: proxyPort, request: request)

    #expect(received == response)
    let recorded = try #require(await upstream.requests().first)
    #expect(recorded.path == "/chat/completions")
    #expect(recorded.method == "POST")
    #expect(recorded.header("authorization") == "Bearer sk-worker-abc")
    #expect(recorded.header("x-worker") == "alpha")
    #expect(recorded.body == requestBody)
    #expect(recorded.header("host") == "127.0.0.1:\(upstreamPort)")
    await upstream.stop()
}

@Test func stripsTheOpenRouterRoutePrefix() async throws {
    let response = ProxyTestSupport.response(body: Data(#"{"ok":true}"#.utf8))
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(
        prefix: "openrouter",
        upstreamPort: upstreamPort,
        upstreamPath: "/api/v1"
    )
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }

    let request = ProxyTestSupport.request(
        path: "/openrouter/chat/completions?stream=true",
        headers: ["Authorization": "Bearer sk-or-123"],
        body: Data(#"{"model":"openai/gpt-4o-mini"}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)

    let recorded = try #require(await upstream.requests().first)
    #expect(recorded.path == "/api/v1/chat/completions?stream=true")
    #expect(recorded.header("authorization") == "Bearer sk-or-123")
    await upstream.stop()
}

@Test func rejectsAnUnknownRouteWithoutForwarding() async throws {
    let response = ProxyTestSupport.response(body: Data(#"{"ok":true}"#.utf8))
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }

    let request = ProxyTestSupport.request(
        path: "/mystery/chat",
        headers: ["Authorization": "Bearer sk-worker-abc"]
    )
    let received = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let text = String(bytes: received, encoding: .utf8) ?? ""

    #expect(text.hasPrefix("HTTP/1.1 404 Not Found"))
    #expect(text.contains("Unknown route /mystery/chat"))
    #expect(text.contains("/deepseek"))
    #expect(await upstream.requests().isEmpty)
    await upstream.stop()
}

@Test func linksAWorkerToItsWorkingDirectory() async throws {
    let cwd = ProxyTestSupport.workspace
    let lookup = FakeProcessLookup(
        clientPID: 4_242,
        factsByPID: [
            4_242: ProcessFacts(processID: 4_242, parentProcessID: 1, workingDirectory: cwd)
        ]
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"model":"deepseek-chat","usage":{"prompt_tokens":3,"completion_tokens":1}}"#.utf8)
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(
        routes: [route],
        processLookup: lookup
    )
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: ["Authorization": "Bearer sk-worker-abc"],
        body: Data(#"{"model":"deepseek-chat"}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let worker = try #require(ProxyTestSupport.workers(in: collected).first)

    #expect(worker.id == "worker-4242")
    #expect(worker.provider == "deepseek")
    #expect(worker.projectPath == cwd)
    #expect(worker.parentSessionID == nil)
    await upstream.stop()
}

@Test func linksAWorkerToTheMatchingOrchestrator() async throws {
    let cwd = ProxyTestSupport.workspace
    let lookup = FakeProcessLookup(
        clientPID: 4_242,
        factsByPID: [
            4_242: ProcessFacts(processID: 4_242, parentProcessID: 4_100, workingDirectory: cwd),
            4_100: ProcessFacts(processID: 4_100, parentProcessID: 1, workingDirectory: cwd),
        ]
    )
    let orchestrators = FakeOrchestratorLookup(
        sessionsByWorkspace: [
            cwd: [OrchestratorSession(sessionID: "session-a", processID: 4_100)]
        ]
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"model":"deepseek-chat","usage":{"prompt_tokens":3,"completion_tokens":1}}"#.utf8)
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(
        routes: [route],
        processLookup: lookup,
        orchestratorLookup: orchestrators
    )
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: ["Authorization": "Bearer sk-worker-abc"],
        body: Data(#"{"model":"deepseek-chat"}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let worker = try #require(ProxyTestSupport.workers(in: collected).first)

    #expect(worker.parentSessionID == "session-a")
    await upstream.stop()
}

@Test func leavesAnAmbiguousParentUnattributed() async throws {
    let cwd = ProxyTestSupport.workspace
    let lookup = FakeProcessLookup(
        clientPID: 4_242,
        factsByPID: [
            4_242: ProcessFacts(processID: 4_242, parentProcessID: 4_100, workingDirectory: cwd),
            4_100: ProcessFacts(processID: 4_100, parentProcessID: 4_099, workingDirectory: cwd),
            4_099: ProcessFacts(processID: 4_099, parentProcessID: 1, workingDirectory: cwd),
        ]
    )
    let orchestrators = FakeOrchestratorLookup(
        sessionsByWorkspace: [
            cwd: [
                OrchestratorSession(sessionID: "session-a", processID: 4_100),
                OrchestratorSession(sessionID: "session-b", processID: 4_099),
            ]
        ]
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"model":"deepseek-chat","usage":{"prompt_tokens":3,"completion_tokens":1}}"#.utf8)
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(
        routes: [route],
        processLookup: lookup,
        orchestratorLookup: orchestrators
    )
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: ["Authorization": "Bearer sk-worker-abc"],
        body: Data(#"{"model":"deepseek-chat"}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let worker = try #require(ProxyTestSupport.workers(in: collected).first)

    #expect(worker.projectPath == cwd)
    #expect(worker.parentSessionID == nil)
    await upstream.stop()
}

@Test func refusesANonLocalhostBindAddress() async throws {
    let proxy = ProxyServer(
        configuration: ProxyConfiguration(host: "0.0.0.0", port: 0),
        processLookup: FakeProcessLookup()
    )
    let states = await proxy.states()
    await proxy.start()
    var iterator = states.makeAsyncIterator()
    var sawRefusal = false
    while let state = await iterator.next() {
        if case .unavailable(.nonLocalBindAddress(let host)) = state {
            #expect(host == "0.0.0.0")
            sawRefusal = true
            break
        }
    }
    #expect(sawRefusal)
}

@Test func reportsAnOccupiedPort() async throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 0)
    let occupied = try NWListener(using: parameters)
    occupied.newConnectionHandler = { _ in }
    let queue = DispatchQueue(label: "surge.tests.occupied")
    let (states, continuation) = AsyncStream<NWListener.State>.makeStream()
    occupied.stateUpdateHandler = { continuation.yield($0) }
    occupied.start(queue: queue)
    var port: UInt16?
    for await state in states {
        if case .ready = state {
            port = occupied.port?.rawValue
            continuation.finish()
        }
    }
    let occupiedPort = try #require(port)

    let proxy = ProxyServer(
        configuration: ProxyConfiguration(port: occupiedPort),
        processLookup: FakeProcessLookup()
    )
    let proxyStates = await proxy.states()
    await proxy.start()
    var iterator = proxyStates.makeAsyncIterator()
    var reason: ProxyUnavailableReason?
    while let state = await iterator.next() {
        if case .unavailable(let unavailable) = state {
            reason = unavailable
            break
        }
    }
    #expect(reason == .portInUse(port: occupiedPort))
    occupied.cancel()
}
