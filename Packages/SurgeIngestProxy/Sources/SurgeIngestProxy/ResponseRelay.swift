import Foundation
import Network

extension ConnectionPipeline {
    func pumpBody(
        _ head: HTTPResponseHead,
        upstreamReader: ConnectionReader,
        collector: inout ResponseUsageCollector
    ) async throws {
        if head.isChunked {
            try await pumpChunked(upstreamReader, collector: &collector)
        } else if let length = head.contentLength {
            guard length >= 0 else { throw ProxyIOError.malformed("content length") }
            try await pumpFixed(length, upstreamReader, collector: &collector)
        } else {
            try await pumpUntilClose(upstreamReader, collector: &collector)
        }
    }

    func pumpFixed(
        _ length: Int,
        _ reader: ConnectionReader,
        collector: inout ResponseUsageCollector
    ) async throws {
        var remaining = length
        while remaining > 0 {
            let want = min(remaining, Self.transferChunkBytes)
            guard let chunk = try await reader.readSome(maximumLength: want) else {
                throw ProxyIOError.closed
            }
            try await NetworkIO.send(chunk, on: connection)
            collector.consume(chunk)
            remaining -= chunk.count
        }
    }

    func pumpChunked(
        _ reader: ConnectionReader,
        collector: inout ResponseUsageCollector
    ) async throws {
        while true {
            guard let sizeLine = try await reader.readLine() else {
                throw ProxyIOError.closed
            }
            try await NetworkIO.send(sizeLine, on: connection)
            guard let size = ConnectionReader.chunkSize(from: sizeLine) else {
                throw ProxyIOError.malformed("chunk size")
            }
            if size == 0 {
                try await forwardTrailers(reader)
                return
            }
            let rawChunk = try await reader.readExact(size + 2)
            try await NetworkIO.send(rawChunk, on: connection)
            collector.consume(Data(rawChunk.prefix(size)))
        }
    }

    func forwardTrailers(_ reader: ConnectionReader) async throws {
        while true {
            guard let line = try await reader.readLine() else {
                throw ProxyIOError.closed
            }
            try await NetworkIO.send(line, on: connection)
            if ConnectionReader.isBlankLine(line) { return }
        }
    }

    func pumpUntilClose(
        _ reader: ConnectionReader,
        collector: inout ResponseUsageCollector
    ) async throws {
        while let chunk = try await reader.readSome(maximumLength: Self.transferChunkBytes) {
            try await NetworkIO.send(chunk, on: connection)
            collector.consume(chunk)
        }
    }
}
