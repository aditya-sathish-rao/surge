import Foundation

struct HTTPHeader: Sendable, Equatable {
    /// Lowercased name for matching. The raw line is kept so forwarding stays byte for byte.
    let name: String
    let value: String
    let rawLine: Data
}

struct HTTPRequestHead: Sendable, Equatable {
    let method: String
    let target: String
    let version: String
    let headers: [HTTPHeader]

    var contentLength: Int? {
        Self.intValue(forHeader: "content-length", in: headers)
    }

    var isChunked: Bool {
        header("transfer-encoding")?.lowercased().contains("chunked") == true
    }

    var expectsContinue: Bool {
        header("expect")?.lowercased().contains("100-continue") == true
    }

    var wantsClose: Bool {
        if header("connection")?.lowercased().contains("close") == true {
            return true
        }
        return version == "HTTP/1.0" && header("connection")?.lowercased().contains("keep-alive") != true
    }

    func header(_ name: String) -> String? {
        headers.first { $0.name == name }?.value
    }

    var pathAndQuery: (path: String, query: String?)? {
        HTTPTargetParser.parse(target)
    }

    private static func intValue(forHeader name: String, in headers: [HTTPHeader]) -> Int? {
        guard let value = headers.first(where: { $0.name == name })?.value else { return nil }
        return Int(value)
    }
}

struct HTTPResponseHead: Sendable, Equatable {
    let version: String
    let statusCode: Int
    let reason: String
    let headers: [HTTPHeader]

    var contentLength: Int? {
        guard let value = headers.first(where: { $0.name == "content-length" })?.value else {
            return nil
        }
        return Int(value)
    }

    var isChunked: Bool {
        header("transfer-encoding")?.lowercased().contains("chunked") == true
    }

    var contentType: String? {
        header("content-type")
    }

    var wantsClose: Bool {
        if header("connection")?.lowercased().contains("close") == true {
            return true
        }
        return version == "HTTP/1.0" && header("connection")?.lowercased().contains("keep-alive") != true
    }

    var hasBody: Bool {
        if statusCode < 200 || statusCode == 204 || statusCode == 304 {
            return false
        }
        return true
    }

    func header(_ name: String) -> String? {
        headers.first { $0.name == name }?.value
    }
}

enum HTTPTargetParser {
    static func parse(_ target: String) -> (path: String, query: String?)? {
        var pathAndQuery = target
        if let url = URL(string: target), url.scheme != nil {
            pathAndQuery = url.path
            if let query = url.query {
                pathAndQuery += "?" + query
            }
        }
        guard pathAndQuery.hasPrefix("/") else { return nil }
        guard let questionMark = pathAndQuery.firstIndex(of: "?") else {
            return (pathAndQuery, nil)
        }
        let path = String(pathAndQuery[pathAndQuery.startIndex..<questionMark])
        let query = String(pathAndQuery[pathAndQuery.index(after: questionMark)...])
        return (path, query.isEmpty ? nil : query)
    }
}

enum HTTPParser {
    private static let lineSeparator = Data("\r\n".utf8)

    static func requestHead(from data: Data) -> HTTPRequestHead? {
        let lines = headerLines(data)
        guard let first = lines.first else { return nil }
        let parts = text(first).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }
        return HTTPRequestHead(
            method: String(parts[0]),
            target: String(parts[1]),
            version: String(parts[2]),
            headers: lines.dropFirst().compactMap(parseHeader)
        )
    }

    static func responseHead(from data: Data) -> HTTPResponseHead? {
        let lines = headerLines(data)
        guard let first = lines.first else { return nil }
        let parts = text(first).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let status = Int(parts[1]) else { return nil }
        let reason = parts.count == 3 ? String(parts[2]) : ""
        return HTTPResponseHead(
            version: String(parts[0]),
            statusCode: status,
            reason: reason,
            headers: lines.dropFirst().compactMap(parseHeader)
        )
    }

    static func headerLines(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while let separator = data.range(of: lineSeparator, in: start..<data.endIndex) {
            lines.append(Data(data[start..<separator.lowerBound]))
            start = separator.upperBound
        }
        if start < data.endIndex {
            lines.append(Data(data[start...]))
        }
        return lines
    }

    private static func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    private static func parseHeader(_ line: Data) -> HTTPHeader? {
        guard let colon = line.firstIndex(of: UInt8(ascii: ":")) else { return nil }
        let name = text(Data(line[line.startIndex..<colon])).lowercased()
        guard !name.isEmpty else { return nil }
        var valueBytes = Data(line[line.index(after: colon)...])
        while valueBytes.first == 0x20 || valueBytes.first == 0x09 {
            valueBytes.removeFirst()
        }
        while valueBytes.last == 0x20 || valueBytes.last == 0x09 {
            valueBytes.removeLast()
        }
        let value = text(valueBytes)
        return HTTPHeader(name: name, value: value, rawLine: Data(line))
    }
}
