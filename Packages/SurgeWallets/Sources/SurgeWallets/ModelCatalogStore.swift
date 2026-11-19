import Foundation
import SurgeCore

/// Keeps the last known model catalog on disk so an offline launch still uses real numbers.
///
/// The file holds model ids, context windows and rates only. No key and no prompt content ever
/// reaches it.
public struct ModelCatalogStore: Sendable {
    public static let fileName = "model-catalog.json"

    public let directory: URL

    public init(directory: URL = ModelCatalogStore.defaultDirectory) {
        self.directory = directory
    }

    public var fileURL: URL {
        directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    public static var defaultDirectory: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(
                path: "Library/Application Support",
                directoryHint: .isDirectory
            )
        return support.appending(path: "Surge", directoryHint: .isDirectory)
    }

    /// The cached catalog, or an empty one when there is no readable file yet.
    public func load() -> ModelCatalog {
        guard let data = try? Data(contentsOf: fileURL),
            let catalog = try? JSONDecoder().decode(ModelCatalog.self, from: data)
        else {
            return .empty
        }
        return catalog
    }

    /// Best effort: a catalog that cannot be written is still usable for this launch.
    public func save(_ catalog: ModelCatalog) {
        guard catalog.isEmpty == false else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(catalog)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
