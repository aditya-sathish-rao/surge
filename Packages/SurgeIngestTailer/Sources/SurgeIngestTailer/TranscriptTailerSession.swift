import Foundation
import SurgeCore

// MARK: - Session lookups

extension TranscriptTailer {
    func state(forSession sessionID: String) -> FileState? {
        files.keys.sorted().compactMap { files[$0] }.first { $0.sessionID == sessionID }
    }

    func read(from url: URL, offset: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

}

// MARK: - Appearances and parent links

extension TranscriptTailer {
    /// A sidechain record names the top-level turn that spawned it. Once that turn's session is
    /// known, the session is re-published with the parent link so the store can attach it to the
    /// tree instead of treating it as a peer.
    func resolvePendingParents() {
        for sessionID in unresolvedParentUUIDs.keys.sorted() {
            guard let parentUUID = unresolvedParentUUIDs[sessionID],
                let parentSessionID = messageOwners[parentUUID],
                parentSessionID != sessionID
            else { continue }
            unresolvedParentUUIDs[sessionID] = nil
            guard let path = files.keys.sorted().first(where: { files[$0]?.sessionID == sessionID }),
                var state = files[path],
                state.parentSessionID == nil
            else { continue }
            state.parentSessionID = parentSessionID
            files[path] = state
            publishAppearance(of: state, modelName: state.lastModelName ?? "", at: state.lastActivity)
        }
    }

    func forgetIndexEntries(forSession sessionID: String) {
        for (uuid, owner) in messageOwners where owner == sessionID {
            messageOwners[uuid] = nil
        }
        unresolvedParentUUIDs[sessionID] = nil
    }

    func publishAppearance(of state: FileState, modelName: String, at occurredAt: Date) {
        sink.publish(
            .sessionAppeared(
                SessionDescriptor(
                    id: state.sessionID,
                    projectPath: state.projectPath ?? "",
                    provider: state.provider,
                    modelName: modelName,
                    maxContextWindow: pricing.contextWindow(forModel: modelName) ?? 0,
                    occurredAt: occurredAt,
                    harness: HarnessIdentity(
                        kind: state.sourceKind.harnessKind,
                        version: state.harnessVersion,
                        sessionID: state.sessionID,
                        transport: state.transport
                    ),
                    parentSessionID: state.parentSessionID
                )
            )
        )
    }

}
