import Foundation
import SurgeCore

/// What the widget can say about the snapshot file. A missing, empty, corrupt or newer file reads
/// as unavailable so the widget shows its placeholder instead of failing.
public enum SnapshotLoadResult: Equatable, Sendable {
    case snapshot(SurgeSnapshot)
    case unavailable
}

public enum SnapshotStore {
    public static func load(from url: URL) -> SnapshotLoadResult {
        guard let data = try? Data(contentsOf: url), let snapshot = decode(data) else {
            return .unavailable
        }
        return .snapshot(snapshot)
    }

    /// The app may write dates as ISO 8601 or as the `Codable` default, so both decode.
    public static func decode(_ data: Data) -> SurgeSnapshot? {
        for strategy in dateStrategies {
            guard
                let snapshot = try? decoder(strategy).decode(SurgeSnapshot.self, from: data),
                snapshot.schemaVersion == SurgeSnapshot.currentSchemaVersion
            else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private static func decoder(_ strategy: JSONDecoder.DateDecodingStrategy) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = strategy
        return decoder
    }

    private static var dateStrategies: [JSONDecoder.DateDecodingStrategy] {
        [
            .deferredToDate,
            .iso8601,
            .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                guard let date = try? style.parse(text) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Unreadable date")
                    )
                }
                return date
            },
        ]
    }
}
