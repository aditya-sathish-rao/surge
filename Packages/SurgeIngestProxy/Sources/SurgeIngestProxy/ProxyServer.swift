import Foundation
import Network
import SurgeCore

public actor ProxyServer: WorkerTraffic {
    private static let queueLabel = "com.surge.ingestproxy"
    private static let maximumStateObservers = 16

    public nonisolated let configuration: ProxyConfiguration

    private nonisolated let processLookup: any ProcessLookup
    private nonisolated let orchestratorLookup: any OrchestratorLookup
    private nonisolated let clock: @Sendable () -> Date
    private nonisolated let queue = DispatchQueue(label: ProxyServer.queueLabel, qos: .userInitiated)
    private nonisolated let eventStream: AsyncStream<ProxyEvent>
    private nonisolated let announcer: WorkerAnnouncer

    private var listener: NWListener?
    private var state: ProxyState = .stopped
    private var stateObservers: [UUID: AsyncStream<ProxyState>.Continuation] = [:]
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    public init(
        configuration: ProxyConfiguration = .default,
        processLookup: any ProcessLookup = LibprocProcessLookup(),
        orchestratorLookup: any OrchestratorLookup = EmptyOrchestratorLookup(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.processLookup = processLookup
        self.orchestratorLookup = orchestratorLookup
        self.clock = clock
        let (stream, continuation) = AsyncStream<ProxyEvent>.makeStream()
        self.eventStream = stream
        self.announcer = WorkerAnnouncer(continuation: continuation)
    }

    public nonisolated func events() -> AsyncStream<ProxyEvent> {
        eventStream
    }

    public func currentState() -> ProxyState {
        state
    }

    public func states() -> AsyncStream<ProxyState> {
        let (stream, continuation) = AsyncStream<ProxyState>.makeStream(
            bufferingPolicy: .bufferingNewest(ProxyServer.maximumStateObservers)
        )
        let id = UUID()
        stateObservers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeStateObserver(id) }
        }
        return stream
    }

    public func start() {
        guard listener == nil else { return }
        guard configuration.isLoopbackOnly else {
            update(.unavailable(.nonLocalBindAddress(configuration.host)))
            return
        }
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            update(.unavailable(.listenerFailed("Invalid port \(configuration.port).")))
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = false
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        do {
            let listener = try NWListener(using: parameters)
            self.listener = listener
            update(.starting)
            listener.stateUpdateHandler = { [weak self] listenerState in
                Task { await self?.handleListenerState(listenerState) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                Task { await self.accept(connection) }
            }
            listener.start(queue: queue)
        } catch {
            update(.unavailable(.listenerFailed(error.localizedDescription)))
        }
    }

    public func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        update(.stopped)
    }

    private func handleListenerState(_ listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            guard case .unavailable = state else {
                update(.listening(port: listener?.port?.rawValue ?? configuration.port))
                return
            }
        case .failed(let error):
            update(.unavailable(Self.unavailableReason(for: error, port: configuration.port)))
            listener?.stateUpdateHandler = nil
            listener?.cancel()
            listener = nil
        case .cancelled:
            if case .unavailable = state { return }
            if state == .stopped { return }
            update(.stopped)
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let port = listener?.port?.rawValue ?? configuration.port
        let key = ObjectIdentifier(connection)
        activeConnections[key] = connection
        connection.start(queue: queue)
        let pipeline = ConnectionPipeline(
            connection: connection,
            listeningPort: port,
            configuration: configuration,
            attribution: WorkerAttribution(
                processLookup: processLookup,
                orchestratorLookup: orchestratorLookup
            ),
            announcer: announcer,
            clock: clock,
            queue: queue
        )
        Task.detached(priority: .userInitiated) { [weak self] in
            await pipeline.run()
            await self?.connectionFinished(key)
        }
    }

    private func connectionFinished(_ key: ObjectIdentifier) {
        activeConnections[key] = nil
    }

    private func removeStateObserver(_ id: UUID) {
        stateObservers[id] = nil
    }

    private func update(_ newState: ProxyState) {
        state = newState
        for continuation in stateObservers.values {
            continuation.yield(newState)
        }
    }

    private static func unavailableReason(for error: NWError, port: UInt16) -> ProxyUnavailableReason {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return .portInUse(port: port)
        }
        if case .posix(let code) = error, code == .EACCES {
            return .bindFailed(port: port)
        }
        return .listenerFailed(error.localizedDescription)
    }
}

actor WorkerAnnouncer {
    private let continuation: AsyncStream<ProxyEvent>.Continuation
    private var announcedWorkers: Set<String> = []

    init(continuation: AsyncStream<ProxyEvent>.Continuation) {
        self.continuation = continuation
    }

    func announce(_ descriptor: WorkerDescriptor) {
        guard announcedWorkers.insert(descriptor.id).inserted else { return }
        continuation.yield(.workerAppeared(descriptor))
    }

    func usage(_ usage: ProxyUsage) {
        continuation.yield(.usage(usage))
    }
}
