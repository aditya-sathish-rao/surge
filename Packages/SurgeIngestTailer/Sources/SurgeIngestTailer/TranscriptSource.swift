import Foundation

/// A harness whose transcripts the tailer can read.
public enum TranscriptSourceKind: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case piAgent = "pi"
}

/// The way a source delivers its records.
public enum SourceTransport: String, Codable, Sendable, Equatable {
    /// One JSON object per line, appended to files under the source's root.
    case appendOnlyJSONLFile
}

/// What a saved checkpoint records, so a new tailer resumes where the last one stopped.
public enum CheckpointKind: String, Codable, Sendable, Equatable {
    case byteOffset
}

/// What a source supplies. A false flag means the value is unavailable, never estimated or zero.
public struct SourceCapabilities: Codable, Sendable, Equatable {
    public let transport: SourceTransport
    public let checkpoint: CheckpointKind
    /// The source records token usage for a turn.
    public let providesUsage: Bool
    /// The source records a cost itself, rather than leaving the tailer to price the tokens.
    public let providesCost: Bool
    /// The tailer can publish compaction markers for this source.
    ///
    /// False everywhere today: the frozen event set has `sessionAppeared`, `turnAppended` and
    /// `sessionEnded`, and none of them carries a compaction marker, so no source may claim it.
    public let providesCompactionMarkers: Bool
    /// The source records which session started this one.
    public let providesParentSessionLink: Bool

    public init(
        transport: SourceTransport,
        checkpoint: CheckpointKind,
        providesUsage: Bool,
        providesCost: Bool,
        providesCompactionMarkers: Bool,
        providesParentSessionLink: Bool
    ) {
        self.transport = transport
        self.checkpoint = checkpoint
        self.providesUsage = providesUsage
        self.providesCost = providesCost
        self.providesCompactionMarkers = providesCompactionMarkers
        self.providesParentSessionLink = providesParentSessionLink
    }
}

/// One configured transcript source.
public struct TranscriptSource: Sendable, Equatable {
    public let kind: TranscriptSourceKind
    public let root: URL

    public init(kind: TranscriptSourceKind, root: URL) {
        self.kind = kind
        self.root = root
    }

    public static let defaultClaudeCodeRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects", directoryHint: .isDirectory)

    public static let defaultPiRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".pi/agent/sessions", directoryHint: .isDirectory)

    public static func claudeCode(root: URL = defaultClaudeCodeRoot) -> TranscriptSource {
        TranscriptSource(kind: .claudeCode, root: root)
    }

    public static func pi(root: URL = defaultPiRoot) -> TranscriptSource {
        TranscriptSource(kind: .piAgent, root: root)
    }

    /// Every harness Surge reads today.
    public static let defaults: [TranscriptSource] = [.claudeCode(), .pi()]
}

/// What one configured source is, so a consumer can tell an unavailable value from a missing one.
public struct TranscriptSourceInfo: Sendable, Equatable {
    public let kind: TranscriptSourceKind
    /// The value put on `SessionDescriptor.provider` for this source's sessions.
    public let provider: String
    public let displayName: String
    public let root: URL?
    public let capabilities: SourceCapabilities

    public init(
        kind: TranscriptSourceKind,
        provider: String,
        displayName: String,
        root: URL?,
        capabilities: SourceCapabilities
    ) {
        self.kind = kind
        self.provider = provider
        self.displayName = displayName
        self.root = root
        self.capabilities = capabilities
    }
}
