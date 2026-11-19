import Foundation

/// A finished HTTP exchange, small enough to cross concurrency domains without a URLResponse.
public struct WalletHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
}

public protocol WalletTransport: Sendable {
    func get(_ request: URLRequest) async throws -> WalletHTTPResponse
}

public struct URLSessionWalletTransport: WalletTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ request: URLRequest) async throws -> WalletHTTPResponse {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return WalletHTTPResponse(statusCode: statusCode, body: data)
    }
}
