import Foundation
import SurgeCore

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
    let pricing: PricingTable
    private let clock: @Sendable () -> Date
    let sink = TailerEventSink()
    private var initialOffsets: [String: UInt64]
    var files: [String: FileState] = [:]
    private var watchers: [String: TranscriptFileWatcher] = [:]
    /// Record id to the session that wrote it, so a sidechain turn can name its parent session.
    var messageOwners: [String: String] = [:]
    /// Session id to the parent turn it named before that turn's session was known.
    var unresolvedParentUUIDs: [String: String] = [:]
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
            if let removed = files.removeValue(forKey: path) {
                forgetIndexEntries(forSession: removed.sessionID)
            }
            cancelWatcher(for: path)
        }

        resolvePendingParents()
        endIdleSessions(now: now)
        updateWatchers(discovered, now: now)
    }

    private func makeState(
        for file: SourceFile,
        from adapter: any TranscriptSourceAdapter,
        now: Date
    ) -> FileState {
        FileState(
            sourceKind: adapter.info.kind,
            provider: adapter.info.provider,
            transport: adapter.info.capabilities.transport.harnessTransport,
            sessionID: file.sessionID,
            parentSessionID: file.parentSessionID,
            projectPath: nil,
            harnessVersion: nil,
            lastModelName: nil,
            reader: adapter.makeReader(),
            offset: initialOffset(for: file, now: now),
            pending: Data(),
            fileNumber: file.fileNumber,
            appeared: false,
            ended: false,
            lastActivity: min(file.modificationDate, now),
            cost: SessionCostAccumulator(),
            seenEventIDs: []
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
        if let provider = entry.provider {
            state.provider = provider
        }
        if let version = entry.harnessVersion, state.harnessVersion == nil {
            state.harnessVersion = version
        }
        if let uuid = entry.messageUUID {
            messageOwners[uuid] = state.sessionID
        }
        if let parentUUID = entry.parentUUID {
            unresolvedParentUUIDs[state.sessionID] = parentUUID
        }
        guard let turn = entry.turn else { return }
        // A repeated record id is the same write seen twice: branched, resumed or sub-agent work
        // can repeat one. Its tokens and its cost are already counted.
        if let eventID = turn.eventID, !state.seenEventIDs.insert(eventID).inserted {
            return
        }

        let occurredAt = turn.occurredAt ?? now
        state.lastModelName = turn.model
        // A session that went quiet and then wrote again is a new appearance for the state store.
        if !state.appeared || state.ended {
            state.appeared = true
            state.ended = false
            publishAppearance(of: state, modelName: turn.model, at: occurredAt)
        }
        state.cost.add(turn.cost)
        state.cost.recordHarnessTotal(turn.harnessCumulativeCostUSD)
        sink.publish(
            .turnAppended(
                TurnAppended(
                    sessionID: state.sessionID,
                    modelName: turn.model,
                    inputTokens: turn.inputTokens,
                    outputTokens: turn.outputTokens,
                    cacheHitTokens: turn.cacheHitTokens,
                    currentContextTokens: turn.currentContextTokens,
                    occurredAt: occurredAt,
                    eventID: turn.eventID,
                    harnessReportedCostUSD: turn.harnessCumulativeCostUSD,
                    turnProviderReportedUSD: turn.cost.providerReportedUSD,
                    turnHarnessReportedUSD: turn.cost.harnessReportedUSD
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
    /// Reads the bytes that arrived since the last look, holding an unterminated line for the next
    /// write instead of parsing half of it.
    func read(_ file: SourceFile, from adapter: any TranscriptSourceAdapter, now: Date) {
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
