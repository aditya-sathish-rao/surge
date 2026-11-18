import Dispatch
import Foundation
import SurgeCore

/// A byte offset the tailer resumes from the first time it sees a transcript file.
public struct TailerCheckpoint: Codable, Sendable, Equatable {
    public let path: String
    public let offset: UInt64

    public init(path: String, offset: UInt64) {
        self.path = path
        self.offset = offset
    }
}

/// Tuning points for transcript tailing.
public enum TailerDefaults {
    /// A session is ended once its transcript has had no new bytes for this long.
    public static let sessionEndedIdleSeconds: TimeInterval = 600

    static let sweepSeconds: TimeInterval = 2
    static let transcriptExtension = "jsonl"
    static let subagentsDirectory = "subagents"
}

/// Carries the single event stream a consumer iterates.
final class TailerEventSink: Sendable {
    let stream: AsyncStream<TailerEvent>
    private let continuation: AsyncStream<TailerEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<TailerEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func publish(_ event: TailerEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

/// Watches one transcript file for writes through a `DispatchSource`.
///
/// `@unchecked Sendable` is safe because the only stored value is a `DispatchSource`,
/// which is thread-safe, and the type has no mutable Swift state. `cancel` is idempotent.
final class TranscriptFileWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    init?(path: String, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func cancel() {
        source.cancel()
    }
}
