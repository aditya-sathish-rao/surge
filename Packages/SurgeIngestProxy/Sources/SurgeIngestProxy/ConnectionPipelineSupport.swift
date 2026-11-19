import Foundation
import Network
import SurgeCore

extension ConnectionPipeline {
    func makeUpstreamConnection(_ url: URL) -> NWConnection? {
        guard let host = url.host, let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        let portNumber = url.port ?? defaultPort
        guard portNumber > 0, portNumber <= 65_535,
            let port = NWEndpoint.Port(rawValue: UInt16(portNumber))
        else {
            return nil
        }
        if scheme == "https" {
            let tls = NWProtocolTLS.Options()
            let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
            return NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        }
        return NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
    }

    static func hostHeader(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        let defaultPort = url.scheme?.lowercased() == "https" ? 443 : 80
        guard let port = url.port, port != defaultPort else { return host }
        return "\(host):\(port)"
    }

    static func upstreamPath(base: String, remainder: String) -> String {
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        if remainder.isEmpty || remainder == "/" {
            return trimmedBase.isEmpty ? "/" : trimmedBase + "/"
        }
        return trimmedBase + remainder
    }

    static func isDroppedRequestHeader(_ name: String) -> Bool {
        switch name {
        case "host", "connection", "proxy-connection", "keep-alive", "expect",
            "upgrade", "accept-encoding", "te", "trailer":
            true
        default:
            false
        }
    }
    func makeDescriptor(
        request: ClientRequest,
        client: WorkerAttribution.Result,
        workerID: String,
        provider: Provider
    ) -> WorkerDescriptor {
        WorkerDescriptor(
            id: workerID,
            provider: provider.rawValue,
            modelName: request.modelName ?? "unknown",
            projectPath: client.projectPath,
            parentSessionID: client.parentSessionID,
            occurredAt: clock()
        )
    }

    func sendUnknownRoute(path: String) async throws {
        let routes = configuration.routes.map { "/" + $0.prefix }.joined(separator: " or ")
        let message =
            routes.isEmpty
            ? "No routes are configured on the Surge proxy."
            : "Unknown route \(path). Use \(routes)."
        try await sendError(status: 404, reason: "Not Found", message: message)
    }

    func sendUpstreamFailure() async throws {
        try await sendError(
            status: 502,
            reason: "Bad Gateway",
            message: "The upstream request failed."
        )
    }

    func sendError(status: Int, reason: String, message: String) async throws {
        let body = Data((message + "\n").utf8)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: text/plain; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        try await NetworkIO.send(Data(head.utf8), on: connection)
        try await NetworkIO.send(body, on: connection)
    }
}
