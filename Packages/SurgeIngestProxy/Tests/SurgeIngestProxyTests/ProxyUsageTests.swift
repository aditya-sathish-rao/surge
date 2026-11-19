import Foundation
import SurgeCore
import Testing

@testable import SurgeIngestProxy

@Test func extractsUsageFromAStreamedSSEResponse() async throws {
    let sse = Data(
        """
        data: {"id":"c1","model":"deepseek-chat","choices":[{"delta":{"content":"Hi"}}]}

        data: {"id":"c1","model":"deepseek-chat","choices":[],\
        "usage":{"prompt_tokens":11,"completion_tokens":7,\
        "prompt_cache_hit_tokens":3}}

        data: [DONE]


        """.utf8
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "text/event-stream"],
        body: sse
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: ["Authorization": "Bearer sk-worker-abc"],
        body: Data(#"{"model":"deepseek-chat","stream":true}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let worker = try #require(ProxyTestSupport.workers(in: collected).first)
    let usage = try #require(ProxyTestSupport.usages(in: collected).first)

    #expect(worker.modelName == "deepseek-chat")
    #expect(usage.provider == "deepseek")
    #expect(usage.modelName == "deepseek-chat")
    #expect(usage.inputTokens == 11)
    #expect(usage.outputTokens == 7)
    #expect(usage.cacheHitTokens == 3)
    #expect(usage.currentContextTokens == 11)
    await upstream.stop()
}

@Test func extractsUsageFromAPlainJSONResponse() async throws {
    let body = Data(
        """
        {"model":"anthropic/claude-3.5-sonnet","usage":{"prompt_tokens":20,\
        "completion_tokens":5,"prompt_tokens_details":{"cached_tokens":4}}}
        """.utf8
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: body
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(prefix: "openrouter", upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/openrouter/chat/completions",
        headers: ["Authorization": "Bearer sk-or-123"],
        body: Data(#"{"model":"anthropic/claude-3.5-sonnet"}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let usage = try #require(ProxyTestSupport.usages(in: collected).first)

    #expect(usage.provider == "openrouter")
    #expect(usage.modelName == "anthropic/claude-3.5-sonnet")
    #expect(usage.inputTokens == 20)
    #expect(usage.outputTokens == 5)
    #expect(usage.cacheHitTokens == 4)
    await upstream.stop()
}

@Test func doesNotInventUsageWhenTheResponseHasNone() async throws {
    let body = Data(
        #"{"model":"deepseek-chat","choices":[{"message":{"content":"no usage here"}}]}"#.utf8
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: body
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: ["Authorization": "Bearer sk-worker-abc"],
        body: Data(#"{"model":"deepseek-chat"}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 1)

    #expect(ProxyTestSupport.workers(in: collected).count == 1)
    #expect(ProxyTestSupport.usages(in: collected).isEmpty)
    await upstream.stop()
}

@Test func forwardsAChunkedResponseUntouchedAndStillExtractsUsage() async throws {
    let sse = Data(
        """
        data: {"model":"deepseek-chat","choices":[{"delta":{"content":"a"}}]}

        data: {"model":"deepseek-chat","choices":[],\
        "usage":{"prompt_tokens":9,"completion_tokens":2,\
        "prompt_cache_hit_tokens":1}}

        data: [DONE]


        """.utf8
    )
    let response = ProxyTestSupport.chunkedResponse(
        contentType: "text/event-stream",
        body: sse,
        chunkSize: 37
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/deepseek/chat/completions",
        headers: ["Authorization": "Bearer sk-worker-abc"],
        body: Data(#"{"model":"deepseek-chat","stream":true}"#.utf8)
    )
    let received = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let usage = try #require(ProxyTestSupport.usages(in: collected).first)

    #expect(received == response)
    #expect(usage.inputTokens == 9)
    #expect(usage.outputTokens == 2)
    #expect(usage.cacheHitTokens == 1)
    await upstream.stop()
}

@Test func sseUsageSurvivesLinesSplitAcrossChunks() throws {
    let usageEvent =
        #"data: {"model":"deepseek-reasoner","choices":[],"usage":{"prompt_tokens":42,"#
        + #""completion_tokens":8,"prompt_cache_hit_tokens":2}}"# + "\n\n"
    let payload = usageEvent + "data: [DONE]\n\n"
    var collector = SSEUsageCollector()
    let bytes = Array(payload.utf8)
    for index in stride(from: 0, to: bytes.count, by: 5) {
        let end = min(index + 5, bytes.count)
        collector.consume(Data(bytes[index..<end]))
    }
    let finished = collector.finish()
    let report = try #require(finished)

    #expect(report.modelName == "deepseek-reasoner")
    #expect(report.inputTokens == 42)
    #expect(report.outputTokens == 8)
    #expect(report.cacheHitTokens == 2)
}

@Test func sseWithoutUsageProducesNoReport() throws {
    let payload = "data: {\"model\":\"deepseek-chat\",\"choices\":[{\"delta\":{}}]}\n\ndata: [DONE]\n\n"
    var collector = SSEUsageCollector()
    collector.consume(Data(payload.utf8))
    #expect(collector.finish() == nil)
}

@Test func jsonWithoutUsageProducesNoReport() {
    let data = Data(#"{"model":"deepseek-chat","choices":[]}"#.utf8)
    #expect(JSONUsageParser.report(from: data, fallbackModel: "deepseek-chat") == nil)
}

@Test func passesAnOpenRouterReportedCostThroughAsTheActualFigure() async throws {
    let body = Data(
        """
        {"id":"gen-1","model":"anthropic/claude-3.5-sonnet",\
        "usage":{"prompt_tokens":20,"completion_tokens":5,"cost":0.00123}}
        """.utf8
    )
    let response = ProxyTestSupport.response(
        headers: ["Content-Type": "application/json"],
        body: body
    )
    let upstream = try MockUpstream(response: response)
    let upstreamPort = try await upstream.start()
    let route = try ProxyTestSupport.mockRoute(prefix: "openrouter", upstreamPort: upstreamPort)
    let (proxy, proxyPort) = try await ProxyTestSupport.startProxy(routes: [route])
    defer { Task { await proxy.stop() } }
    let events = proxy.events()

    let request = ProxyTestSupport.request(
        path: "/openrouter/chat/completions",
        headers: ["Authorization": "Bearer sk-or-123"],
        body: Data(#"{"model":"anthropic/claude-3.5-sonnet","usage":{"include":true}}"#.utf8)
    )
    _ = try await ProxyTestSupport.exchange(port: proxyPort, request: request)
    let collected = try await ProxyTestSupport.collectEvents(events, count: 2)
    let usage = try #require(ProxyTestSupport.usages(in: collected).first)

    let reported = try #require(usage.reportedCostUSD)
    #expect(abs(reported - 0.00123) < 0.000_000_1)
    await upstream.stop()
}

@Test func aResponseWithoutACostReportsNoCostRatherThanZero() throws {
    let data = Data(
        #"{"model":"deepseek-chat","usage":{"prompt_tokens":11,"completion_tokens":7}}"#.utf8
    )
    let report = try #require(JSONUsageParser.report(from: data, fallbackModel: "deepseek-chat"))

    #expect(report.reportedCostUSD == nil)
}

@Test func sseCostSurvivesTheFinalUsageEvent() throws {
    let usageEvent =
        #"data: {"model":"openrouter/auto","choices":[],"#
        + #""usage":{"prompt_tokens":10,"completion_tokens":2,"cost":0.0004}}"# + "\n\n"
    let payload = usageEvent + "data: [DONE]\n\n"
    var collector = SSEUsageCollector()
    collector.consume(Data(payload.utf8))
    let finished = collector.finish()
    let report = try #require(finished)

    let reported = try #require(report.reportedCostUSD)
    #expect(abs(reported - 0.0004) < 0.000_000_1)
}

@Test func aNegativeOrUnparseableCostIsIgnored() throws {
    let negative = Data(
        #"{"model":"m","usage":{"prompt_tokens":1,"cost":-0.5}}"#.utf8
    )
    #expect(JSONUsageParser.report(from: negative, fallbackModel: nil)?.reportedCostUSD == nil)

    let text = Data(
        #"{"model":"m","usage":{"prompt_tokens":1,"cost":"variable"}}"#.utf8
    )
    #expect(JSONUsageParser.report(from: text, fallbackModel: nil)?.reportedCostUSD == nil)
}
