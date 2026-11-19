import Foundation
import SurgeCore
import os

/// A temporary `~/.claude/projects` stand-in and a temporary `~/.pi/agent/sessions` stand-in.
/// Every test owns both and never touches the real ones.
struct TailerFixture {
    let root: URL
    let piRoot: URL
    let clock: TestClock

    init(clock: TestClock = TestClock(start: Date())) throws {
        let name = "surge-tailer-\(UUID().uuidString)"
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        let root = temporary.appending(path: name, directoryHint: .isDirectory)
        let piRoot = temporary.appending(path: "\(name)-pi", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: piRoot, withIntermediateDirectories: true)
        self.root = root
        self.piRoot = piRoot
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

    /// `~/.pi/agent/sessions/--<path>--/<timestamp>_<session-id>.jsonl`.
    func piSessionURL(session: String, project: String = "--Users-dev-workspace--") -> URL {
        piRoot.appending(path: project, directoryHint: .isDirectory)
            .appending(path: "2026-11-18T10-00-00-000Z_\(session).jsonl")
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
        try? FileManager.default.removeItem(at: piRoot)
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
    /// The record's own id. Nil leaves it out, as older transcripts do.
    var uuid: String?
    var parentUuid: String?
    var isSidechain: Bool?
    var version: String?
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
        var record: [String: Any] = [
            "type": "assistant",
            "sessionId": turn.session,
            "cwd": turn.cwd,
            "timestamp": turn.timestamp,
            "message": [
                "model": turn.model,
                "usage": usage,
            ],
        ]
        if let uuid = turn.uuid { record["uuid"] = uuid }
        if let parentUuid = turn.parentUuid { record["parentUuid"] = parentUuid }
        if let isSidechain = turn.isSidechain { record["isSidechain"] = isSidechain }
        if let version = turn.version { record["version"] = version }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Claude Code's own running total, written after a turn. `hasUnknownModelCost` disqualifies it.
    static func costState(
        session: String,
        totalCostUSD: Double,
        hasUnknownModelCost: Bool = false
    ) throws -> String {
        let record: [String: Any] = [
            "type": "cost-state",
            "sessionId": session,
            "timestamp": "2026-11-18T10:00:01.000Z",
            "totalCostUSD": totalCostUSD,
            "hasUnknownModelCost": hasUnknownModelCost,
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

/// One assistant turn in the shape pi writes, with metadata and numbers only.
struct PiTurnFixture {
    var model: String? = "claude-sonnet-5-5"
    /// The provider family pi names on the message. Nil leaves the field out.
    var provider: String? = "anthropic"
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning: Int?
    /// Nil leaves the cost object out, as an older session with no priced provider does.
    var costTotal: Double?
    /// Nil leaves `totalFromProvider` out, which pi treats as its own estimate.
    var totalFromProvider: Bool?
    var timestamp = "2026-11-18T10:00:00.000Z"
    var content = "assistant text"
}

enum PiSessionFixtures {
    static let secondTimestamp = "2026-11-18T10:00:05.000Z"

    static func header(
        session: String = "session-1",
        cwd: String = "/Users/dev/workspace",
        timestamp: String = "2026-11-18T09:59:59.000Z"
    ) throws -> String {
        try line([
            "type": "session",
            "version": 3,
            "id": session,
            "timestamp": timestamp,
            "cwd": cwd,
        ])
    }

    static func turn(_ turn: PiTurnFixture) throws -> String {
        var usage: [String: Any] = [
            "input": turn.input,
            "output": turn.output,
            "cacheRead": turn.cacheRead,
            "cacheWrite": turn.cacheWrite,
            "totalTokens": turn.input + turn.output + turn.cacheRead + turn.cacheWrite,
        ]
        if let reasoning = turn.reasoning {
            usage["reasoning"] = reasoning
        }
        if let total = turn.costTotal {
            var cost: [String: Any] = [
                "input": 0.0,
                "output": 0.0,
                "cacheRead": 0.0,
                "cacheWrite": 0.0,
                "total": total,
            ]
            if let totalFromProvider = turn.totalFromProvider {
                cost["totalFromProvider"] = totalFromProvider
            }
            usage["cost"] = cost
        }
        var message: [String: Any] = [
            "role": "assistant",
            "content": [["type": "text", "text": turn.content]],
            "usage": usage,
            "stopReason": "stop",
            "timestamp": 1_794_996_000_000,
        ]
        if let model = turn.model {
            message["model"] = model
        }
        if let provider = turn.provider {
            message["provider"] = provider
        }
        return try line([
            "type": "message",
            "id": "b2c3d4e5",
            "parentId": "a1b2c3d4",
            "timestamp": turn.timestamp,
            "message": message,
        ])
    }

    static func modelChange(
        _ modelID: String,
        timestamp: String = "2026-11-18T10:00:03.000Z"
    ) throws -> String {
        try line([
            "type": "model_change",
            "id": "d4e5f6g7",
            "parentId": "c3d4e5f6",
            "timestamp": timestamp,
            "provider": "anthropic",
            "modelId": modelID,
        ])
    }

    static func thinkingLevelChange(_ level: String = "high") throws -> String {
        try line([
            "type": "thinking_level_change",
            "id": "e5f6g7h8",
            "parentId": "d4e5f6g7",
            "timestamp": "2026-11-18T10:00:04.000Z",
            "thinkingLevel": level,
        ])
    }

    static func custom(customType: String = "my-extension") throws -> String {
        try line([
            "type": "custom",
            "id": "h8i9j0k1",
            "parentId": "g7h8i9j0",
            "timestamp": "2026-11-18T10:00:05.000Z",
            "customType": customType,
            "data": ["count": 42],
        ])
    }

    static func customMessage(customType: String = "my-extension", content: String) throws -> String {
        try line([
            "type": "custom_message",
            "id": "i9j0k1l2",
            "parentId": "h8i9j0k1",
            "timestamp": "2026-11-18T10:00:06.000Z",
            "customType": customType,
            "content": content,
            "display": true,
        ])
    }

    static func compaction(tokensBefore: Int = 50_000) throws -> String {
        try line([
            "type": "compaction",
            "id": "f6g7h8i9",
            "parentId": "e5f6g7h8",
            "timestamp": "2026-11-18T10:00:07.000Z",
            "summary": "earlier conversation",
            "firstKeptEntryId": "c3d4e5f6",
            "tokensBefore": tokensBefore,
        ])
    }

    static func usageEntry(
        kind: String = "cache_warm",
        cacheRead: Int = 50_000,
        costTotal: Double = 0.015
    ) throws -> String {
        try line([
            "type": "usage",
            "id": "f6g7h8i9",
            "parentId": "e5f6g7h8",
            "timestamp": "2026-11-18T10:00:08.000Z",
            "kind": kind,
            "provider": "anthropic",
            "model": "claude-sonnet-5-5",
            "usage": [
                "input": 0,
                "output": 0,
                "cacheRead": cacheRead,
                "cacheWrite": 0,
                "totalTokens": cacheRead,
                "cost": [
                    "input": 0.0,
                    "output": 0.0,
                    "cacheRead": costTotal,
                    "cacheWrite": 0.0,
                    "total": costTotal,
                ],
            ],
        ])
    }

    private static func line(_ record: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
