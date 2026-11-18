import Foundation

/// A known orchestrator session and the process that owns it.
public struct OrchestratorSession: Sendable, Equatable, Hashable {
    public let sessionID: String
    public let processID: pid_t

    public init(sessionID: String, processID: pid_t) {
        self.sessionID = sessionID
        self.processID = processID
    }
}

/// Boundary the app can fill with the sessions the transcript tailer has found.
public protocol OrchestratorLookup: Sendable {
    func orchestrators(inWorkspaceAt path: String) -> [OrchestratorSession]
}

public struct EmptyOrchestratorLookup: OrchestratorLookup {
    public init() {}

    public func orchestrators(inWorkspaceAt path: String) -> [OrchestratorSession] {
        []
    }
}

struct WorkerAttribution: Sendable {
    struct Result: Sendable, Equatable {
        let processID: pid_t?
        let projectPath: String
        let parentSessionID: String?
    }

    private static let ancestryLimit = 64

    let processLookup: any ProcessLookup
    let orchestratorLookup: any OrchestratorLookup

    func attribute(sourcePort: UInt16, destinationPort: UInt16) -> Result {
        guard
            let pid = processLookup.clientProcessID(
                sourcePort: sourcePort,
                destinationPort: destinationPort
            )
        else {
            return Result(processID: nil, projectPath: "", parentSessionID: nil)
        }
        let projectPath = processLookup.facts(forPID: pid)?.workingDirectory ?? ""
        let ancestors = Self.ancestry(startingAt: pid, using: processLookup)
        let orchestrators =
            projectPath.isEmpty
            ? [] : orchestratorLookup.orchestrators(inWorkspaceAt: projectPath)
        return Result(
            processID: pid,
            projectPath: projectPath,
            parentSessionID: Self.parentSessionID(ancestors: ancestors, orchestrators: orchestrators)
        )
    }

    static func ancestry(startingAt pid: pid_t, using lookup: any ProcessLookup) -> [pid_t] {
        var ancestors: [pid_t] = []
        var visited: Set<pid_t> = []
        var current = pid
        while ancestors.count < ancestryLimit, current > 1, visited.insert(current).inserted {
            ancestors.append(current)
            guard let facts = lookup.facts(forPID: current), facts.parentProcessID > 1 else { break }
            current = facts.parentProcessID
        }
        return ancestors
    }

    /// Exactly one orchestrator in the workspace must sit in the caller's ancestry.
    /// Two matches are ambiguous, so the worker attaches to the workspace with no parent.
    static func parentSessionID(
        ancestors: [pid_t],
        orchestrators: [OrchestratorSession]
    ) -> String? {
        let ancestorSet = Set(ancestors)
        let matched = Set(orchestrators.filter { ancestorSet.contains($0.processID) }.map(\.sessionID))
        guard matched.count == 1 else { return nil }
        return matched.first
    }
}
