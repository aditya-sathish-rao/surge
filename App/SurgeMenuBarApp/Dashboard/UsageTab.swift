import SurgeCore
import SurgeUI
import SwiftUI

/// The Usage tab: throughput for the last 30 minutes, token totals, then context by agent.
struct UsageTab: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            if model.workspaces.isEmpty {
                SurgeCard { SurgeEmptyState() }
            } else {
                SurgeCard {
                    ThroughputChart(samples: model.throughputSamples)
                }
                SurgeCard {
                    VStack(alignment: .leading, spacing: SurgeSpacing.section) {
                        TokenTotalsList(workspaces: model.workspaces)
                        ContextByAgentList(workspaces: model.workspaces, now: model.now)
                    }
                }
            }
        }
    }
}
