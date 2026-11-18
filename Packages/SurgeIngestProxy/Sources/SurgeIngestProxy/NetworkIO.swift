import Foundation
import Network

enum ProxyIOError: Error {
    case closed
    case malformed(String)
    case tooLarge(String)
}

enum NetworkIO {
    static func send(_ data: Data, on connection: NWConnection) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
        }
    }

    /// Returns nil at end of stream. Empty but incomplete reads are retried.
    static func receive(_ connection: NWConnection, maximumLength: Int = 65_536) async throws -> Data? {
        while true {
            let result = try await receiveOnce(connection, maximumLength: maximumLength)
            if let data = result.data, !data.isEmpty {
                return data
            }
            if result.isComplete {
                return nil
            }
        }
    }

    private static func receiveOnce(
        _ connection: NWConnection,
        maximumLength: Int
    ) async throws -> (data: Data?, isComplete: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }
}

final class ConnectionReader {
    private static let headerSeparator = Data("\r\n\r\n".utf8)

    private let connection: NWConnection
    private var buffer = Data()

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func readHead(maximumBytes: Int) async throws -> Data? {
        while true {
            if let range = buffer.range(of: Self.headerSeparator) {
                let head = Data(buffer[buffer.startIndex..<range.upperBound])
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return head
            }
            guard buffer.count <= maximumBytes else {
                throw ProxyIOError.tooLarge("HTTP head")
            }
            guard let chunk = try await NetworkIO.receive(connection) else {
                if buffer.isEmpty {
                    return nil
                }
                throw ProxyIOError.closed
            }
            buffer.append(chunk)
        }
    }

    func readExact(_ count: Int) async throws -> Data {
        guard count >= 0 else { throw ProxyIOError.malformed("negative length") }
        while buffer.count < count {
            guard let chunk = try await NetworkIO.receive(connection) else {
                throw ProxyIOError.closed
            }
            buffer.append(chunk)
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    func readSome(maximumLength: Int) async throws -> Data? {
        guard maximumLength > 0 else { return Data() }
        if !buffer.isEmpty {
            let count = min(maximumLength, buffer.count)
            let result = Data(buffer.prefix(count))
            buffer.removeFirst(count)
            return result
        }
        return try await NetworkIO.receive(connection, maximumLength: maximumLength)
    }

    /// Returns one CRLF-terminated line, including the terminator.
    func readLine(maximumBytes: Int = 8_192) async throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex...newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            guard buffer.count <= maximumBytes else {
                throw ProxyIOError.tooLarge("HTTP line")
            }
            guard let chunk = try await NetworkIO.receive(connection) else {
                if buffer.isEmpty {
                    return nil
                }
                throw ProxyIOError.closed
            }
            buffer.append(chunk)
        }
    }

    /// Reads a chunked body without decoding it, so it can be forwarded exactly as sent.
    func readChunkedBody(maximumBytes: Int) async throws -> Data {
        var body = Data()
        while true {
            guard let sizeLine = try await readLine() else {
                throw ProxyIOError.closed
            }
            body.append(sizeLine)
            guard let size = Self.chunkSize(from: sizeLine) else {
                throw ProxyIOError.malformed("chunk size")
            }
            guard body.count <= maximumBytes else {
                throw ProxyIOError.tooLarge("request body")
            }
            if size == 0 {
                try await appendTrailers(to: &body, maximumBytes: maximumBytes)
                return body
            }
            let chunk = try await readExact(size + 2)
            body.append(chunk)
            guard body.count <= maximumBytes else {
                throw ProxyIOError.tooLarge("request body")
            }
        }
    }

    static func chunkSize(from line: Data) -> Int? {
        var text = String(bytes: line, encoding: .utf8) ?? ""
        if let semicolon = text.firstIndex(of: ";") {
            text = String(text[text.startIndex..<semicolon])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let size = Int(text, radix: 16), size >= 0 else { return nil }
        return size
    }

    static func isBlankLine(_ line: Data) -> Bool {
        let trimmed = line.drop { $0 == 0x0D || $0 == 0x0A || $0 == 0x20 || $0 == 0x09 }
        return trimmed.isEmpty
    }

    private func appendTrailers(to body: inout Data, maximumBytes: Int) async throws {
        while true {
            guard let trailer = try await readLine() else {
                throw ProxyIOError.closed
            }
            body.append(trailer)
            guard body.count <= maximumBytes else {
                throw ProxyIOError.tooLarge("request body")
            }
            if Self.isBlankLine(trailer) {
                return
            }
        }
    }
}
