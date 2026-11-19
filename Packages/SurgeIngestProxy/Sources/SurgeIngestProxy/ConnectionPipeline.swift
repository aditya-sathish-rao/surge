import Foundation
import Network
import SurgeCore

struct ConnectionPipeline: Sendable {
    private static let maximumHeaderBytes = 65_536
    private static let maximumRequestBytes = 32 * 1_048_576
    static let transferChunkBytes = 65_536
    private static let crlf = Data("\r\n".utf8)

    let connection: NWConnection
    let listeningPort: UInt16
    let configuration: ProxyConfiguration
    let attribution: WorkerAttribution
    let announcer: WorkerAnnouncer
    let clock: @Sendable () -> Date
    let queue: DispatchQueue

    func run() async {
        defer { connection.cancel() }
        let client = attribution.attribute(
            sourcePort: Self.remotePort(of: connection) ?? 0,
            destinationPort: listeningPort
        )
        let workerID = Self.workerID(for: client)
        let reader = ConnectionReader(connection)
        while !Task.isCancelled {
            do {
                guard let request = try await readRequest(reader) else { return }
                let shouldClose = try await forward(request, client: client, workerID: workerID, reader: reader)
                if shouldClose { return }
            } catch {
                return
            }
        }
    }

    private func readRequest(_ reader: ConnectionReader) async throws -> ClientRequest? {
        guard let rawHead = try await reader.readHead(maximumBytes: Self.maximumHeaderBytes) else {
            return nil
        }
        guard let head = HTTPParser.requestHead(from: Data(rawHead.dropLast(4))),
            let pathAndQuery = head.pathAndQuery
        else {
            try await sendError(status: 400, reason: "Bad Request", message: "Malformed HTTP request.")
            return nil
        }
        if head.expectsContinue {
            try await NetworkIO.send(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), on: connection)
        }
        let body: Data
        do {
            body = try await readBody(head: head, reader: reader)
        } catch ProxyIOError.tooLarge(_) {
            try await sendError(
                status: 413,
                reason: "Content Too Large",
                message: "The request body is too large for the Surge proxy."
            )
            return nil
        }
        return ClientRequest(
            head: head,
            body: body,
            path: pathAndQuery.path,
            query: pathAndQuery.query,
            modelName: JSONUsageParser.model(from: body)
        )
    }

    private func readBody(head: HTTPRequestHead, reader: ConnectionReader) async throws -> Data {
        if head.isChunked {
            return try await reader.readChunkedBody(maximumBytes: Self.maximumRequestBytes)
        }
        guard let length = head.contentLength else { return Data() }
        guard length >= 0, length <= Self.maximumRequestBytes else {
            throw ProxyIOError.tooLarge("request body")
        }
        guard length > 0 else { return Data() }
        return try await reader.readExact(length)
    }

    private func forward(
        _ request: ClientRequest,
        client: WorkerAttribution.Result,
        workerID: String,
        reader: ConnectionReader
    ) async throws -> Bool {
        guard let match = configuration.route(forPath: request.path) else {
            try await sendUnknownRoute(path: request.path)
            return true
        }
        let provider = Provider(providerID: match.route.prefix) ?? .other
        await announcer.announce(
            makeDescriptor(
                request: request,
                client: client,
                workerID: workerID,
                provider: provider
            )
        )
        guard let upstream = makeUpstreamConnection(match.route.upstream) else {
            try await sendError(
                status: 502,
                reason: "Bad Gateway",
                message: "The upstream URL for this route is not valid."
            )
            return true
        }
        defer { upstream.cancel() }
        upstream.start(queue: queue)
        return try await relay(
            request,
            match: match,
            provider: provider,
            upstream: upstream,
            workerID: workerID
        )
    }

    private func relay(
        _ request: ClientRequest,
        match: RouteMatch,
        provider: Provider,
        upstream: NWConnection,
        workerID: String
    ) async throws -> Bool {
        let upstreamReader = ConnectionReader(upstream)
        var didSendResponseHead = false
        do {
            try await NetworkIO.send(upstreamHead(for: request, match: match), on: upstream)
            try await NetworkIO.send(request.body, on: upstream)
            let (head, rawHead) = try await readFinalResponseHead(upstreamReader)
            try await NetworkIO.send(rawHead, on: connection)
            didSendResponseHead = true
            let close = try await relayBody(
                head,
                request: request,
                provider: provider,
                workerID: workerID,
                upstreamReader: upstreamReader
            )
            return close
        } catch {
            if !didSendResponseHead {
                try await sendUpstreamFailure()
            }
            return true
        }
    }

    private func readFinalResponseHead(
        _ reader: ConnectionReader
    ) async throws -> (HTTPResponseHead, Data) {
        while true {
            guard let rawHead = try await reader.readHead(maximumBytes: Self.maximumHeaderBytes) else {
                throw ProxyIOError.closed
            }
            guard let head = HTTPParser.responseHead(from: Data(rawHead.dropLast(4))) else {
                throw ProxyIOError.malformed("response head")
            }
            if head.statusCode >= 100, head.statusCode < 200, head.statusCode != 101 {
                try await NetworkIO.send(rawHead, on: connection)
                continue
            }
            return (head, rawHead)
        }
    }

    private func relayBody(
        _ head: HTTPResponseHead,
        request: ClientRequest,
        provider: Provider,
        workerID: String,
        upstreamReader: ConnectionReader
    ) async throws -> Bool {
        var collector = ResponseUsageCollector(
            contentType: head.contentType,
            fallbackModel: request.modelName
        )
        if request.head.method != "HEAD", head.hasBody {
            try await pumpBody(head, upstreamReader: upstreamReader, collector: &collector)
        }
        if let report = collector.finish() {
            await announcer.usage(
                ProxyUsage(
                    workerID: workerID,
                    provider: provider.rawValue,
                    modelName: report.modelName ?? request.modelName ?? "unknown",
                    inputTokens: report.inputTokens,
                    outputTokens: report.outputTokens,
                    cacheHitTokens: report.cacheHitTokens,
                    currentContextTokens: report.inputTokens,
                    occurredAt: clock(),
                    reportedCostUSD: report.reportedCostUSD
                )
            )
        }
        return request.head.wantsClose || head.wantsClose
    }

    private func upstreamHead(for request: ClientRequest, match: RouteMatch) throws -> Data {
        guard let host = Self.hostHeader(for: match.route.upstream) else {
            throw ProxyIOError.malformed("upstream host")
        }
        var target = Self.upstreamPath(base: match.route.upstream.path, remainder: match.path)
        if let query = request.query {
            target += "?" + query
        }
        var head = Data("\(request.head.method) \(target) HTTP/1.1\r\n".utf8)
        head.append(Data("Host: \(host)\r\n".utf8))
        // Identity encoding keeps the body readable for usage extraction while forwarding it unchanged.
        head.append(Data("Accept-Encoding: identity\r\n".utf8))
        for header in request.head.headers where !Self.isDroppedRequestHeader(header.name) {
            head.append(header.rawLine)
            head.append(Self.crlf)
        }
        head.append(Data("Connection: close\r\n\r\n".utf8))
        return head
    }

    private static func workerID(for client: WorkerAttribution.Result) -> String {
        if let pid = client.processID {
            return "worker-\(pid)"
        }
        return "worker-\(UUID().uuidString.lowercased())"
    }

    private static func remotePort(of connection: NWConnection) -> UInt16? {
        guard case .hostPort(_, let port) = connection.endpoint else { return nil }
        return port.rawValue
    }
}

struct ClientRequest {
    let head: HTTPRequestHead
    let body: Data
    let path: String
    let query: String?
    let modelName: String?
}
