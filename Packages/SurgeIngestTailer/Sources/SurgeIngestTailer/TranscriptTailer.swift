import Foundation
import SurgeCore

/// Tails Claude Code transcripts under `~/.claude/projects` and publishes immutable events.
///
/// One JSONL file is one session. Each file keeps its own byte offset and its unterminated
/// trailing line, so a write only decodes the bytes that arrived since the last read and a
/// line split across two writes is joined before it is parsed. A sub-agent is a transcript
/// inside a `subagents/` folder; its parent session is the folder that contains `subagents/`.
///
/// Transcripts are read for metadata and token counts only. `TranscriptRecord` declares no
/// content keys, so prompt and response text never enters this package's memory.
public actor TranscriptTailer: SessionTailing {
    public static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects", directoryHint: .isDirectory)

    public static let bundledPricing: PricingTable =
        (try? PricingTable.bundled()) ?? PricingTable(models: [:])

    private struct FileState {
        let sessionID: String
        let parentSessionID: String?
        var projectPath: String?
        var offset: UInt64
        var pending: Data
        var fileNumber: UInt64?
        var appeared: Bool
        var ended: Bool
        var lastActivity: Date
    }

    private let scanner: TranscriptScanner
    private let pricing: PricingTable
    private let clock: @Sendable () -> Date
    private let sink = TailerEventSink()
    private var initialOffsets: [String: UInt64]
    private var files: [String: FileState] = [:]
    private var watchers: [String: TranscriptFileWatcher] = [:]
    private var sweepTask: Task<Void, Never>?
    private var isMonitoring = false

    /// - Parameters:
    ///   - root: The projects directory that holds the transcript folders. Injected by tests.
    ///   - checkpoints: Offsets saved by a previous tailer, so an app restart resumes instead of replaying.
    ///   - pricing: The table that supplies each model's context window.
    ///   - clock: Injected so idle sessions and ended detection are deterministic in tests.
    public init(
        root: URL = TranscriptTailer.defaultRoot,
        checkpoints: [TailerCheckpoint] = [],
        pricing: PricingTable = TranscriptTailer.bundledPricing,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scanner = TranscriptScanner(root: root, now: clock)
        self.pricing = pricing
        self.clock = clock
        self.initialOffsets = Dictionary(
            checkpoints.map { ($0.path, $0.offset) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Returns the event stream and starts watching. The stream is created once and shared.
    public nonisolated func events() -> AsyncStream<TailerEvent> {
        Task { await self.start() }
        return sink.stream
    }

    /// Starts the sweep that catches new files and files that have gone quiet.
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(TailerDefaults.sweepSeconds))
            }
        }
    }

    /// Stops watching and completes the event stream.
    public func shutdown() {
        sweepTask?.cancel()
        sweepTask = nil
        isMonitoring = false
        for watcher in watchers.values {
            watcher.cancel()
        }
        watchers.removeAll()
        sink.finish()
    }

    /// Offsets to hand to a new tailer so it resumes from the same bytes.
    public func checkpoints() -> [TailerCheckpoint] {
        files.keys.sorted().compactMap { path in
            guard let state = files[path] else { return nil }
            let pendingBytes = UInt64(state.pending.count)
            // Resume at the start of an unterminated line so the line is read whole again.
            let offset = state.offset >= pendingBytes ? state.offset - pendingBytes : 0
            return TailerCheckpoint(path: path, offset: offset)
        }
    }

    /// The session that spawned this sub-agent, or nil for a top-level session.
    public func parentSessionID(forSession sessionID: String) -> String? {
        files.keys.sorted().compactMap { files[$0] }.first { $0.sessionID == sessionID }?.parentSessionID
    }

    /// Reads new bytes from every transcript and publishes what changed.
    public func refresh() {
        let now = clock()
        let discovered = scanner.discover()
        var seen = Set<String>()

        for file in discovered {
            seen.insert(file.path)
            var state = files[file.path] ?? makeState(for: file, now: now)
            if let previous = state.fileNumber, let current = file.fileNumber, previous != current {
                // The file was replaced, so the saved offset points into a different file.
                state.offset = 0
                state.pending = Data()
            }
            if let current = file.fileNumber {
                state.fileNumber = current
            }
            if file.size < state.offset {
                // The file was truncated; read it again from the start.
                state.offset = 0
                state.pending = Data()
            }
            if file.size > state.offset, let data = read(from: file.url, offset: state.offset) {
                state.offset += UInt64(data.count)
                state.lastActivity = now
                state.pending.append(data)
                drain(&state, now: now)
            }
            files[file.path] = state
        }

        for path in Array(files.keys) where !seen.contains(path) {
            files.removeValue(forKey: path)
            cancelWatcher(for: path)
        }

        endIdleSessions(now: now)
        updateWatchers(discovered, now: now)
    }

    private func makeState(for file: TranscriptFile, now: Date) -> FileState {
        FileState(
            sessionID: file.sessionID,
            parentSessionID: file.parentSessionID,
            projectPath: nil,
            offset: initialOffset(for: file, now: now),
            pending: Data(),
            fileNumber: file.fileNumber,
            appeared: false,
            ended: false,
            lastActivity: min(file.modificationDate, now)
        )
    }

    /// A recently written transcript is read from the start so its first turn is visible at
    /// launch. An older transcript is tailed from its end instead of replaying its history.
    private func initialOffset(for file: TranscriptFile, now: Date) -> UInt64 {
        if let saved = initialOffsets[file.path] {
            return saved
        }
        let age = now.timeIntervalSince(file.modificationDate)
        return age < TailerDefaults.sessionEndedIdleSeconds ? 0 : file.size
    }

    private func read(from url: URL, offset: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

    /// Parses complete lines and keeps the unterminated remainder for the next write.
    private func drain(_ state: inout FileState, now: Date) {
        while let newline = state.pending.firstIndex(of: 0x0A) {
            let length = state.pending.distance(from: state.pending.startIndex, to: newline)
            let line = Data(state.pending.prefix(length))
            state.pending.removeFirst(length + 1)
            process(line, state: &state, now: now)
        }
    }

    private func process(_ line: Data, state: inout FileState, now: Date) {
        guard
            !line.isEmpty,
            let record = try? JSONDecoder().decode(TranscriptRecord.self, from: line)
        else { return }

        let entry = record.parse()
        if let projectPath = entry.projectPath {
            state.projectPath = projectPath
        }
        guard let turn = entry.turn else { return }

        let occurredAt = turn.occurredAt ?? now
        let contextTokens = turn.inputTokens + turn.cacheReadTokens + turn.cacheCreationTokens
        // A session that went quiet and then wrote again is a new appearance for the state store.
        if !state.appeared || state.ended {
            state.appeared = true
            state.ended = false
            sink.publish(
                .sessionAppeared(
                    SessionDescriptor(
                        id: state.sessionID,
                        projectPath: state.projectPath ?? "",
                        provider: TranscriptRecord.provider,
                        modelName: turn.model,
                        maxContextWindow: pricing.contextWindow(forModel: turn.model) ?? 0,
                        occurredAt: occurredAt
                    )
                )
            )
        }
        sink.publish(
            .turnAppended(
                TurnAppended(
                    sessionID: state.sessionID,
                    modelName: turn.model,
                    inputTokens: turn.inputTokens,
                    outputTokens: turn.outputTokens,
                    cacheHitTokens: turn.cacheReadTokens,
                    currentContextTokens: contextTokens,
                    occurredAt: occurredAt
                )
            )
        )
    }

    private func endIdleSessions(now: Date) {
        for path in files.keys.sorted() {
            guard
                var state = files[path],
                state.appeared,
                !state.ended,
                now.timeIntervalSince(state.lastActivity) >= TailerDefaults.sessionEndedIdleSeconds
            else { continue }
            state.ended = true
            files[path] = state
            sink.publish(.sessionEnded(sessionID: state.sessionID, occurredAt: now))
        }
    }

    private func updateWatchers(_ discovered: [TranscriptFile], now: Date) {
        let idleWindow = TailerDefaults.sessionEndedIdleSeconds
        for file in discovered {
            let isRecent = now.timeIntervalSince(file.modificationDate) < idleWindow
            let shouldWatch = isRecent && files[file.path]?.ended != true
            if shouldWatch {
                if watchers[file.path] == nil {
                    startWatcher(for: file.path)
                }
            } else {
                cancelWatcher(for: file.path)
            }
        }
    }

    private func startWatcher(for path: String) {
        guard
            let watcher = TranscriptFileWatcher(
                path: path,
                onChange: { [weak self] in
                    guard let self else { return }
                    Task { await self.refresh() }
                })
        else { return }
        watchers[path] = watcher
    }

    private func cancelWatcher(for path: String) {
        watchers.removeValue(forKey: path)?.cancel()
    }
}
