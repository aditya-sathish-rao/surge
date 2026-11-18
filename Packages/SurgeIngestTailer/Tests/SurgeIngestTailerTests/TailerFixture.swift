import Foundation
import SurgeCore
import os

/// A temporary `~/.claude/projects` stand-in. Every test owns one and never touches the real one.
struct TailerFixture {
    let root: URL
    let clock: TestClock

    init(clock: TestClock = TestClock(start: Date())) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "surge-tailer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        self.clock = clock
    }

    func sessionURL(session: String, project: String = "project-alpha") -> URL {
        root.appending(path: project, directoryHint: .isDirectory)
            .appending(path: "\(session).jsonl")
    }

    func subagentURL(agent: String, parent: String, project: String = "project-alpha") -> URL {
        root.appending(path: project, directoryHint: .isDirectory)
            .appending(path: parent, directoryHint: .isDirectory)
            .appending(path: "subagents", directoryHint: .isDirectory)
            .appending(path: "agent-\(agent).jsonl")
    }

    func append(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// Truncates the file in place, keeping its identity, then writes new content.
    func truncate(to text: String, at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// Atomically replaces the file with a different one, so its identity changes.
    func replaceFile(at url: URL, with text: String) throws {
        // The replacement is written outside the projects root so the tailer never sees it.
        let replacement = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "surge-replacement-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: replacement)
        defer { try? FileManager.default.removeItem(at: replacement) }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A clock the test advances by hand.
final class TestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    init(start: Date) {
        state = OSAllocatedUnfairLock(initialState: start)
    }

    func now() -> Date {
        state.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// One assistant turn in the shape Claude Code writes, with metadata and token counts only.
struct TurnFixture {
    var session = "session-1"
    var model = "claude-sonnet-5-5"
    var cwd = "/Users/dev/workspace"
    var input = 0
    var output = 0
    var cacheRead: Int?
    var cacheCreation: Int?
    var timestamp = "2026-11-18T10:00:00.000Z"
}

enum TranscriptFixtures {
    static let firstTimestamp = Date(timeIntervalSince1970: 1_794_996_000)
    static let secondTimestamp = Date(timeIntervalSince1970: 1_794_996_005)

    static func turn(_ turn: TurnFixture) throws -> String {
        var usage: [String: Any] = [
            "input_tokens": turn.input,
            "output_tokens": turn.output,
        ]
        if let cacheRead = turn.cacheRead {
            usage["cache_read_input_tokens"] = cacheRead
        }
        if let cacheCreation = turn.cacheCreation {
            usage["cache_creation_input_tokens"] = cacheCreation
        }
        let record: [String: Any] = [
            "type": "assistant",
            "sessionId": turn.session,
            "cwd": turn.cwd,
            "timestamp": turn.timestamp,
            "message": [
                "model": turn.model,
                "usage": usage,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    static func metadataLine(type: String, session: String) throws -> String {
        let record: [String: Any] = [
            "type": type,
            "sessionId": session,
            "timestamp": "2026-11-18T09:59:59.000Z",
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

/// Collects events from the tailer stream so tests can wait for a count without cancelling
/// the shared stream, and can assert that nothing arrived inside a short window.
final class EventRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock<[TailerEvent]>(initialState: [])
    private let consumer: Task<Void, Never>

    init(_ stream: AsyncStream<TailerEvent>) {
        let storage = storage
        consumer = Task {
            for await event in stream {
                storage.withLock { $0.append(event) }
            }
        }
    }

    deinit {
        consumer.cancel()
    }

    func wait(forCount count: Int, timeout: Duration = .seconds(5)) async -> [TailerEvent] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let snapshot = storage.withLock { $0 }
            if snapshot.count >= count {
                return snapshot
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return storage.withLock { $0 }
    }

    func recordedEvents() -> [TailerEvent] {
        storage.withLock { $0 }
    }
}

func turns(in events: [TailerEvent]) -> [TurnAppended] {
    events.compactMap { event in
        if case .turnAppended(let turn) = event {
            return turn
        }
        return nil
    }
}

func appeared(in events: [TailerEvent]) -> [SessionDescriptor] {
    events.compactMap { event in
        if case .sessionAppeared(let descriptor) = event {
            return descriptor
        }
        return nil
    }
}

func ended(in events: [TailerEvent]) -> [String] {
    events.compactMap { event in
        if case .sessionEnded(let sessionID, _) = event {
            return sessionID
        }
        return nil
    }
}
