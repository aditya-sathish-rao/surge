import AppIntents
import Foundation
import SurgeCore

/// One project the widget can be filtered to. The list comes from the snapshot the app writes, so
/// the configuration screen never invents a workspace.
struct WorkspaceEntity: AppEntity, Equatable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workspace")
    static let defaultQuery = WorkspaceEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WorkspaceEntityQuery: EntityStringQuery {
    func entities(for identifiers: [WorkspaceEntity.ID]) async throws -> [WorkspaceEntity] {
        let wanted = Set(identifiers)
        return load().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WorkspaceEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return load() }
        return load().filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    func suggestedEntities() async throws -> [WorkspaceEntity] {
        load()
    }

    private func load() -> [WorkspaceEntity] {
        guard case .snapshot(let snapshot) = SnapshotStore.load(from: SnapshotLocation.fileURL()) else {
            return []
        }
        return WidgetSelection.orderedWorkspaces(snapshot.workspaces).map {
            WorkspaceEntity(id: $0.id.uuidString, name: $0.name)
        }
    }
}

/// The only setting a widget instance has: all workspaces, or one project (PRD 7.5).
struct SurgeWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Surge"
    static let description = IntentDescription("Show all workspaces or one project.")

    @Parameter(title: "Workspace", description: "All workspaces unless you pick one.")
    var workspace: WorkspaceEntity?
}
