import Foundation
import SurgeCore

/// What the tailer keeps for one transcript file.
private struct FileState {
    let sourceKind: TranscriptSourceKind
    let provider: String
    let sessionID: String
    let parentSessionID: String?
    var projectPath: String?
    var reader: any TranscriptFileReader
    var offset: UInt64
    var pending: Data
    var fileNumber: UInt64?
    var appeared: Bool
    var ended: Bool
    var lastActivity: Date
    var cost: SessionCostAccumulator
}

/// Tails the configured transcript sources and publishes immutable events.
///
/// Each source adapter says where its files live, what a line means and what it can supply. One
/// JSONL file is one session. Each file keeps its own byte offset and its unterminated trailing
/// line, so a write only decodes the bytes that arrived since the last read and a line split
/// across two writes is joined before it is parsed.
///
/// Transcripts are read for metadata and numbers only. The record types declare no content keys,
/// so prompt, response and tool-output text never enters this package's memory.
public actor TranscriptTailer: SessionTailing {
    public static let defaultRoot = TranscriptSource.defaultClaudeCodeRoot

    public static let bundledPricing: PricingTable =
        (try? PricingTable.bundled()) ?? PricingTable(models: [:])

    private let adapters: [any TranscriptSourceAdapter]
    private let infoByKind: [TranscriptSourceKind: TranscriptSourceInfo]
    private let pricing: PricingTable
    private let clock: @Sendable () -> Date
    private let sink = TailerEventSink()
    private var initialOffsets: [String: UInt64]
    private var files: [String: FileState] = [:]
    private var watchers: [String: TranscriptFileWatcher] = [:]
    private var sweepTask: Task<Void, Never>?
    private var isMonitoring = false

    /// What each configured source is, including what it can and cannot supply.
    public nonisolated let sources: [TranscriptSourceInfo]

    /// - Parameters:
    ///   - sources: The transcript sources to read. The default is every harness Surge supports;
    ///     pass a single source, pointed at a test directory, to tail one harness in isolation.
    ///   - checkpoints: Offsets saved by a previous tailer, so an app restart resumes instead of replaying.
    ///   - pricing: The table that supplies each model's context window and a locally estimated cost.
    ///   - clock: Injected so idle sessions and ended detection are deterministic in tests.
    public init(
        sources: [TranscriptSource] = TranscriptSource.defaults,
        checkpoints: [TailerCheckpoint] = [],
        pricing: PricingTable = TranscriptTailer.bundledPricing,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            adapters: sources.map { TranscriptTailer.adapter(for: $0, pricing: pricing, clock: clock) },
            checkpoints: checkpoints,
            pricing: pricing,
            clock: clock
        )
    }

    /// Takes adapters directly, so a source that is not shipped yet can be tailed in a test.
    init(
        adapters: [any TranscriptSourceAdapter],
        checkpoints: [TailerCheckpoint] = [],
        pricing: PricingTable = TranscriptTailer.bundledPricing,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.adapters = adapters
        self.sources = adapters.map(\.info)
        self.infoByKind = Dictionary(adapters.map { ($0.info.kind, $0.info) }) { first, _ in first }
        self.pricing = pricing
        self.clock = clock
        self.initialOffsets = Dictionary(
            checkpoints.map { ($0.path, $0.offset) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private static func adapter(
        for source: TranscriptSource,
        pricing: PricingTable,
        clock: @escaping @Sendable () -> Date
    ) -> any TranscriptSourceAdapter {
        switch source.kind {
        case .claudeCode:
            ClaudeCodeAdapter(root: source.root, pricing: pricing, now: clock)
        case .piAgent:
            PiSessionAdapter(root: source.root, pricing: pricing, now: clock)
        }
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

    /// Reads new bytes from every source and publishes what changed.
    public func refresh() {
        let now = clock()
        var discovered: [SourceFile] = []
        var seen = Set<String>()

        for adapter in adapters {
            for file in adapter.discover(now: now) {
                discovered.append(file)
                seen.insert(file.path)
                read(file, from: adapter, now: now)
            }
        }

        for path in Array(files.keys) where !seen.contains(path) {
            files.removeValue(forKey: path)
            cancelWatcher(for: path)
        }

        endIdleSessions(now: now)
        updateWatchers(discovered, now: now)
    }

    private func state(forSession sessionID: String) -> FileState? {
        files.keys.sorted().compactMap { files[$0] }.first { $0.sessionID == sessionID }
    }

    private func read(_ file: SourceFile, from adapter: any TranscriptSourceAdapter, now: Date) {
        var state = files[file.path] ?? makeState(for: file, from: adapter, now: now)
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

    private func makeState(
        for file: SourceFile,
        from adapter: any TranscriptSourceAdapter,
        now: Date
    ) -> FileState {
        FileState(
            sourceKind: adapter.info.kind,
            provider: adapter.info.provider,
            sessionID: file.sessionID,
            parentSessionID: file.parentSessionID,
            projectPath: nil,
            reader: adapter.makeReader(),
            offset: initialOffset(for: file, now: now),
            pending: Data(),
            fileNumber: file.fileNumber,
            appeared: false,
            ended: false,
            lastActivity: min(file.modificationDate, now),
            cost: SessionCostAccumulator()
        )
    }

    /// A recently written transcript is read from the start so its first turn is visible at
    /// launch. An older transcript is tailed from its end instead of replaying its history.
    private func initialOffset(for file: SourceFile, now: Date) -> UInt64 {
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
        guard !line.isEmpty else { return }
        let entry = state.reader.ingest(line: line, at: now)
        if let projectPath = entry.projectPath {
            state.projectPath = projectPath
        }
        guard let turn = entry.turn else { return }

        let occurredAt = turn.occurredAt ?? now
        // A session that went quiet and then wrote again is a new appearance for the state store.
        if !state.appeared || state.ended {
            state.appeared = true
            state.ended = false
            sink.publish(
                .sessionAppeared(
                    SessionDescriptor(
                        id: state.sessionID,
                        projectPath: state.projectPath ?? "",
                        provider: state.provider,
                        modelName: turn.model,
                        maxContextWindow: pricing.contextWindow(forModel: turn.model) ?? 0,
                        occurredAt: occurredAt
                    )
                )
            )
        }
        state.cost.add(turn.cost)
        sink.publish(
            .turnAppended(
                TurnAppended(
                    sessionID: state.sessionID,
                    modelName: turn.model,
                    inputTokens: turn.inputTokens,
                    outputTokens: turn.outputTokens,
                    cacheHitTokens: turn.cacheHitTokens,
                    currentContextTokens: turn.currentContextTokens,
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

    private func updateWatchers(_ discovered: [SourceFile], now: Date) {
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

extension TranscriptTailer {
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
    ///
    /// Nil is also the answer when the session's source cannot supply a parent link, which
    /// `capabilities(forSession:)` reports. Nothing is inferred from a process or a workspace.
    public func parentSessionID(forSession sessionID: String) -> String? {
        state(forSession: sessionID)?.parentSessionID
    }

    /// What the session's source can supply, or nil when the session is not being tailed.
    public func capabilities(forSession sessionID: String) -> SourceCapabilities? {
        guard let state = state(forSession: sessionID) else { return nil }
        return infoByKind[state.sourceKind]?.capabilities
    }

    /// The cost recorded for a session, kept split by provenance. Nil when the session is not tailed.
    public func cost(forSession sessionID: String) -> SessionCost? {
        guard let state = state(forSession: sessionID) else { return nil }
        return state.cost.summary(sessionID: state.sessionID, provider: state.provider)
    }
}
