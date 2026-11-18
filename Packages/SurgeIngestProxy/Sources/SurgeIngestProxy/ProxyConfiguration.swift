import Foundation
import Network

/// A worker route: a path prefix on the local proxy and the upstream base URL it forwards to.
public struct ProxyRoute: Sendable, Equatable, Hashable {
    public let prefix: String
    public let upstream: URL

    public init(prefix: String, upstream: URL) {
        self.prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.upstream = upstream
    }

    /// The DeepSeek and OpenRouter routes workers use by default.
    public static var defaults: [ProxyRoute] {
        var routes: [ProxyRoute] = []
        if let deepseek = URL(string: "https://api.deepseek.com") {
            routes.append(ProxyRoute(prefix: "deepseek", upstream: deepseek))
        }
        if let openrouter = URL(string: "https://openrouter.ai/api/v1") {
            routes.append(ProxyRoute(prefix: "openrouter", upstream: openrouter))
        }
        return routes
    }
}

public struct ProxyConfiguration: Sendable, Equatable {
    public static let loopbackHost = "127.0.0.1"
    public static let defaultPort: UInt16 = 8899

    public let host: String
    public let port: UInt16
    public let routes: [ProxyRoute]

    public init(
        host: String = ProxyConfiguration.loopbackHost,
        port: UInt16 = ProxyConfiguration.defaultPort,
        routes: [ProxyRoute] = ProxyRoute.defaults
    ) {
        self.host = host
        self.port = port
        self.routes = routes
    }

    public static var `default`: ProxyConfiguration {
        ProxyConfiguration()
    }

    /// Surge only ever listens on the loopback interface.
    public var isLoopbackOnly: Bool {
        host == ProxyConfiguration.loopbackHost || host == "localhost"
    }

    func route(forPath path: String) -> RouteMatch? {
        for route in routes where !route.prefix.isEmpty {
            let prefix = "/" + route.prefix
            guard path == prefix || path.hasPrefix(prefix + "/") else { continue }
            var remainder = String(path.dropFirst(prefix.count))
            if remainder.isEmpty {
                remainder = "/"
            }
            return RouteMatch(route: route, path: remainder)
        }
        return nil
    }
}

struct RouteMatch: Sendable, Equatable {
    let route: ProxyRoute
    let path: String
}

public enum ProxyState: Sendable, Equatable {
    case stopped
    case starting
    case listening(port: UInt16)
    case unavailable(ProxyUnavailableReason)
}

public enum ProxyUnavailableReason: Sendable, Equatable {
    case nonLocalBindAddress(String)
    case portInUse(port: UInt16)
    case bindFailed(port: UInt16)
    case listenerFailed(String)

    /// Plain-English reason the app can show next to "No signal".
    public var reasonText: String {
        switch self {
        case .nonLocalBindAddress(let host):
            "Surge only listens on 127.0.0.1, not \(host)."
        case .portInUse(let port):
            "Port \(port) is already in use."
        case .bindFailed(let port):
            "Could not bind the proxy to 127.0.0.1:\(port)."
        case .listenerFailed(let message):
            "The proxy listener failed: \(message)"
        }
    }
}
