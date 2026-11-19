import SurgeCore
import SurgeUI
import SwiftUI

/// The Spend tab: the 14-day daily spend chart, today by provider, then balances.
///
/// Every number carries its label: actual where a provider reports the cost, derived from a
/// balance drop for DeepSeek, and estimated everywhere else.
struct SpendTab: View {
    let model: AppModel
    @Environment(\.colorSchemeContrast) private var systemContrast

    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            SurgeCard {
                DailySpendChart(
                    days: model.dailySpend,
                    range: .fourteenDays,
                    source: model.todaySpendSource
                )
            }
            SurgeCard {
                SpendByProviderBar(
                    shares: SpendShares.make(for: model.todaySpendPoint, source: model.todaySpendSource)
                )
            }
            SurgeCard {
                VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
                    SurgeSectionLabel("How spend is counted")
                    Text(
                        "Provider reported is the bill the provider itself sent. Harness reported is "
                            + "the harness's own total at list prices. Balance derived is a drop in the "
                            + "account's balance. Quota window is burn against a subscription window. "
                            + "Estimated is worked out locally from the model's published rates."
                    )
                    .font(SurgeTypography.meta)
                    .foregroundStyle(SurgeInk.tertiary(systemContrast))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            BalancesCard(balances: model.storeModel.balances, now: model.now)
        }
    }
}
