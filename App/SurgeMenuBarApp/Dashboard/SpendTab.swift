import SurgeCore
import SurgeUI
import SwiftUI

/// The Spend tab: the 14-day daily spend chart, today by provider, then balances.
struct SpendTab: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            SurgeCard {
                DailySpendChart(days: model.dailySpend, range: .fourteenDays)
            }
            SurgeCard {
                SpendByProviderBar(shares: SpendShares.make(for: model.todaySpendPoint))
            }
            BalancesCard(balances: model.storeModel.balances, now: model.now)
        }
    }
}
