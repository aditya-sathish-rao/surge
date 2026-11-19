import Foundation
import SurgeCore

/// Where the widget reads its snapshot from.
///
/// Signing is not available before the MVP, so there is no App Group container yet. The local MVP
/// location lives under Application Support behind this one type, so moving to the App Group
/// container later is a change to `localMVP` alone.
struct SnapshotLocation: Equatable, Sendable {
    /// The kind the widget registers with WidgetKit. Task 08 reads the same constant.
    static let widgetKind = "SurgeAgents"
    static let fileName = "snapshot.json"

    let directory: URL

    var fileURL: URL {
        directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    static func local(fileManager: FileManager = .default) -> SnapshotLocation {
        let support =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(
                path: "Library/Application Support",
                directoryHint: .isDirectory
            )
        return SnapshotLocation(directory: support.appending(path: "Surge", directoryHint: .isDirectory))
    }
}

/// Reads and writes the one snapshot file, atomically.
///
/// Dates use `JSONEncoder`'s default strategy (seconds since the reference date) so the widget
/// extension needs no custom configuration to decode the file.
struct SnapshotFileStore: Sendable {
    let location: SnapshotLocation

    init(location: SnapshotLocation = .local()) {
        self.location = location
    }

    func write(_ snapshot: SurgeSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try write(data)
    }

    func write(_ data: Data) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let temporary = location.directory.appending(
            path: ".snapshot-\(UUID().uuidString).json",
            directoryHint: .notDirectory
        )
        try data.write(to: temporary, options: .atomic)
        // `rename` replaces the destination in one step, so a reader sees either the old snapshot
        // or the new one and never a half-written file.
        guard rename(temporary.path, location.fileURL.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func read() -> SurgeSnapshot? {
        guard let data = try? Data(contentsOf: location.fileURL) else { return nil }
        return try? JSONDecoder().decode(SurgeSnapshot.self, from: data)
    }
}
