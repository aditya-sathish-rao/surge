import Foundation

/// The one place the snapshot file location lives.
///
/// `SurgeMenuBarApp` writes the snapshot and the widget reads it, so both sides resolve the path
/// here rather than spelling one out. Development runs without an App Group entitlement, so the
/// fallback is the application support folder the app uses until signing exists.
public enum SnapshotLocation {
    public static let appGroupIdentifier = "group.com.adityarao.surge"
    public static let folderName = "Surge"
    public static let fileName = "snapshot.json"

    /// The App Group container once the entitlement exists, application support until then.
    public static func fileURL(fileManager: FileManager = .default) -> URL {
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return container.appendingPathComponent(fileName, isDirectory: false)
        }
        return applicationSupportDirectory(fileManager: fileManager).appendingPathComponent(fileName)
    }

    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(folderName, isDirectory: true)
    }
}
