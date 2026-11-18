import Foundation
import Network
import SurgeCore
import Testing

@testable import SurgeIngestProxy

enum TestError: Error {
    case timeout
    case noPort
    case unavailable(String)
    case badPort
}

struct RecordedRequest: Sendable {
    let requestLine: String
    let headers: [String: String]
    let body: Data

    var method: String {
        requestLine.split(separator: " ").first.map(String.init) ?? ""
    }

    var path: String {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return "" }
        return String(parts[1])
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

actor MockUpstream {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "surge.tests.mock-upstream")
    private let response: Data
    private var recorded: [RecordedRequest] = []

    init(response: Data) throws {
        self.response = response
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 0)
        self.listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        let (states, continuation) = AsyncStream<NWListener.State>.makeStream()
        listener.stateUpdateHandler = { continuation.yield($0) }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connection.start(queue: self.queue)
            Task { await self.handle(connection) }
        }
        listener.start(queue: queue)
        for await state in states {
            switch state {
            case .ready:
                continuation.finish()
                guard let port = listener.port?.rawValue else { throw TestError.noPort }
                return port
            case .failed(let error):
                continuation.finish()
                throw error
            default:
                break
            }
        }
        throw TestError.noPort
    }

    func requests() -> [RecordedRequest] {
        recorded
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) async {
        defer { connection.cancel() }
        let reader = ConnectionReader(connection)
        guard let rawHead = try? await reader.readHead(maximumBytes: 65_536),
            let head = HTTPParser.requestHead(from: Data(rawHead.dropLast(4)))
        else {
            return
        }
        let length = head.contentLength ?? 0
        guard let body = try? await reader.readExact(length) else { return }
        recorded.append(
            RecordedRequest(
                requestLine: [head.method, head.target, head.version].joined(separator: " "),
                headers: Dictionary(
                    head.headers.map { ($0.name, $0.value) },
                    uniquingKeysWith: { first, _ in first }
                ),
                body: body
            )
        )
        for index in stride(from: 0, to: response.count, by: 4_096) {
            let end = min(index + 4_096, response.count)
            let chunk = Data(response[index..<end])
            do {
                try await NetworkIO.send(chunk, on: connection)
            } catch {
                return
            }
        }
    }
}

struct FakeProcessLookup: ProcessLookup {
    let clientPID: pid_t?
    let factsByPID: [pid_t: ProcessFacts]

    init(clientPID: pid_t? = 4_242, factsByPID: [pid_t: ProcessFacts] = [:]) {
        self.clientPID = clientPID
        self.factsByPID = factsByPID
    }

    func clientProcessID(sourcePort: UInt16, destinationPort: UInt16) -> pid_t? {
        clientPID
    }

    func facts(forPID pid: pid_t) -> ProcessFacts? {
        factsByPID[pid]
    }
}

struct FakeOrchestratorLookup: OrchestratorLookup {
    let sessionsByWorkspace: [String: [OrchestratorSession]]

    init(sessionsByWorkspace: [String: [OrchestratorSession]] = [:]) {
        self.sessionsByWorkspace = sessionsByWorkspace
    }

    func orchestrators(inWorkspaceAt path: String) -> [OrchestratorSession] {
        sessionsByWorkspace[path] ?? []
    }
}

enum ProxyTestSupport {
    static let workspace = "/Users/test/project"

    static func startProxy(
        routes: [ProxyRoute],
        processLookup: any ProcessLookup = FakeProcessLookup(),
        orchestratorLookup: any OrchestratorLookup = EmptyOrchestratorLookup(),
        clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_763_000_000) }
    ) async throws -> (ProxyServer, UInt16) {
        let proxy = ProxyServer(
            configuration: ProxyConfiguration(port: 0, routes: routes),
            processLookup: processLookup,
            orchestratorLookup: orchestratorLookup,
            clock: clock
        )
        let states = await proxy.states()
        await proxy.start()
        var iterator = states.makeAsyncIterator()
        while let state = await iterator.next() {
            switch state {
            case .listening(let port):
                return (proxy, port)
            case .unavailable(let reason):
                throw TestError.unavailable(reason.reasonText)
            default:
                break
            }
        }
        throw TestError.noPort
    }

    static func mockRoute(
        prefix: String = "deepseek",
        upstreamPort: UInt16,
        upstreamPath: String = ""
    ) throws -> ProxyRoute {
        let url = try #require(URL(string: "http://127.0.0.1:\(upstreamPort)\(upstreamPath)"))
        return ProxyRoute(prefix: prefix, upstream: url)
    }

    static func request(
        path: String,
        headers: [String: String] = [:],
        body: Data = Data(),
        method: String = "POST"
    ) -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: 127.0.0.1:8899\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func response(
        status: String = "200 OK",
        headers: [String: String] = [:],
        body: Data
    ) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func chunkedResponse(
        contentType: String,
        body: Data,
        chunkSize: Int
    ) -> Data {
        var data = Data(
            """
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Transfer-Encoding: chunked\r
            Connection: close\r
            \r\n
            """.utf8
        )
        var index = body.startIndex
        while index < body.endIndex {
            let end = min(index + chunkSize, body.endIndex)
            let chunk = body[index..<end]
            data.append(Data("\(String(chunk.count, radix: 16))\r\n".utf8))
            data.append(contentsOf: chunk)
            data.append(Data("\r\n".utf8))
            index = end
        }
        data.append(Data("0\r\n\r\n".utf8))
        return data
    }

    static func exchange(port: UInt16, request: Data) async throws -> Data {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw TestError.badPort
        }
        let connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
        let queue = DispatchQueue(label: "surge.tests.client")
        connection.start(queue: queue)
        defer { connection.cancel() }
        try await NetworkIO.send(request, on: connection)
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var response = Data()
                while let chunk = try await NetworkIO.receive(connection) {
                    response.append(chunk)
                }
                return response
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw TestError.timeout
            }
            guard let result = try await group.next() else { throw TestError.timeout }
            group.cancelAll()
            return result
        }
    }

    static func collectEvents(
        _ stream: AsyncStream<ProxyEvent>,
        count: Int
    ) async throws -> [ProxyEvent] {
        try await withThrowingTaskGroup(of: [ProxyEvent].self) { group in
            group.addTask {
                var events: [ProxyEvent] = []
                var iterator = stream.makeAsyncIterator()
                while events.count < count {
                    guard let event = await iterator.next() else { break }
                    events.append(event)
                }
                return events
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw TestError.timeout
            }
            guard let result = try await group.next() else { throw TestError.timeout }
            group.cancelAll()
            return result
        }
    }

    static func workers(in events: [ProxyEvent]) -> [WorkerDescriptor] {
        events.compactMap { event in
            if case .workerAppeared(let worker) = event { return worker }
            return nil
        }
    }

    static func usages(in events: [ProxyEvent]) -> [ProxyUsage] {
        events.compactMap { event in
            if case .usage(let usage) = event { return usage }
            return nil
        }
    }
}
