import Foundation

/// One transcript file found under the projects root.
struct TranscriptFile {
    let url: URL
    let path: String
    let sessionID: String
    let parentSessionID: String?
    let modificationDate: Date
    let size: UInt64
    let fileNumber: UInt64?
}

/// Walks the projects root and describes every transcript file it finds.
struct TranscriptScanner {
    let root: URL
    let now: @Sendable () -> Date

    func discover() -> [TranscriptFile] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }

        let rootComponents = root.standardizedFileURL.pathComponents
        var found: [TranscriptFile] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == TailerDefaults.transcriptExtension else { continue }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = (attributes[.size] as? NSNumber)?.uint64Value
            else { continue }
            let components = url.standardizedFileURL.pathComponents
            guard components.count > rootComponents.count else { continue }
            let relative = Array(components.dropFirst(rootComponents.count))
            found.append(
                TranscriptFile(
                    url: url,
                    path: url.path,
                    sessionID: url.deletingPathExtension().lastPathComponent,
                    parentSessionID: parentSessionID(in: relative),
                    modificationDate: (attributes[.modificationDate] as? Date) ?? now(),
                    size: size,
                    fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
                )
            )
        }
        return found.sorted { $0.path < $1.path }
    }

    /// `<project>/<session>/subagents/agent-x.jsonl` belongs to session `<session>`.
    private func parentSessionID(in relativeComponents: [String]) -> String? {
        guard
            let index = relativeComponents.firstIndex(of: TailerDefaults.subagentsDirectory),
            index >= 2
        else { return nil }
        return relativeComponents[index - 1]
    }
}
