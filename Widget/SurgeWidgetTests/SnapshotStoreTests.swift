import Foundation
import SurgeCore
import Testing

@testable import SurgeWidgetLogic

struct SnapshotStoreTests {
    @Test func aMissingFileReadsAsUnavailable() {
        let directory = makeTemporaryDirectory()
        defer { remove(directory) }

        #expect(SnapshotStore.load(from: directory.appendingPathComponent("missing.json")) == .unavailable)
    }

    @Test func anEmptyOrCorruptFileReadsAsUnavailable() {
        let directory = makeTemporaryDirectory()
        defer { remove(directory) }

        #expect(SnapshotStore.load(from: write(Data(), in: directory)) == .unavailable)
        #expect(SnapshotStore.load(from: write(Data("{ not json".utf8), in: directory)) == .unavailable)
        #expect(SnapshotStore.load(from: write(Data("[]".utf8), in: directory)) == .unavailable)
        #expect(SnapshotStore.load(from: write(Data("{}".utf8), in: directory)) == .unavailable)
    }

    @Test func aSnapshotWrittenByTheAppLoads() throws {
        let directory = makeTemporaryDirectory()
        defer { remove(directory) }
        let data = try JSONEncoder().encode(SurgeFixtures.snapshot)

        guard case .snapshot(let snapshot) = SnapshotStore.load(from: write(data, in: directory)) else {
            Issue.record("Expected the snapshot to load")
            return
        }
        #expect(snapshot == SurgeFixtures.snapshot)
    }

    @Test func isoDatesLoadToo() throws {
        let directory = makeTemporaryDirectory()
        defer { remove(directory) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(SurgeFixtures.snapshot)

        guard case .snapshot(let snapshot) = SnapshotStore.load(from: write(data, in: directory)) else {
            Issue.record("Expected the ISO 8601 snapshot to load")
            return
        }
        #expect(snapshot.workspaces.count == SurgeFixtures.snapshot.workspaces.count)
    }

    @Test func aNewerSchemaReadsAsUnavailableRatherThanGuessing() throws {
        let directory = makeTemporaryDirectory()
        defer { remove(directory) }
        let snapshot = WidgetTestFixtures.snapshot(
            workspaces: WidgetTestFixtures.snapshot.workspaces,
            schemaVersion: SurgeSnapshot.currentSchemaVersion + 1
        )
        let data = try JSONEncoder().encode(snapshot)

        #expect(SnapshotStore.load(from: write(data, in: directory)) == .unavailable)
    }

    @Test func theSnapshotLivesBehindOneLocation() {
        let support = SnapshotLocation.applicationSupportDirectory()

        #expect(support.lastPathComponent == SnapshotLocation.folderName)
        #expect(SnapshotLocation.fileURL().lastPathComponent == SnapshotLocation.fileName)
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("surge-widget-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ data: Data, in directory: URL) -> URL {
        let url = directory.appendingPathComponent(SnapshotLocation.fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            Issue.record("Could not write the test snapshot: \(error)")
        }
        return url
    }

    private func remove(_ directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Could not clean up the test directory: \(error)")
        }
    }
}
