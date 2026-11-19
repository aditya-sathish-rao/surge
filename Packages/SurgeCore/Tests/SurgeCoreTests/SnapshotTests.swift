import Foundation
import SurgeCore
import Testing

struct SnapshotTests {
    @Test func snapshotRoundTripsThroughJSONWithVersion() throws {
        let snapshot = SurgeFixtures.snapshot
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SurgeSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == SurgeSnapshot.currentSchemaVersion)
        #expect(decoded.schemaVersion == 1)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
    }

    @Test func statusWithAssociatedValueSurvivesTheRoundTrip() throws {
        let snapshot = SurgeFixtures.snapshot
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SurgeSnapshot.self, from: data)
        let stalledSince = SurgeFixtures.referenceDate.addingTimeInterval(-380)

        #expect(decoded.workspaces[0].workers[0].status == .stalled(since: stalledSince))
        #expect(decoded.workspaces[0].workers[1].status == .waitingForYou)
    }

    @Test func snapshotStalenessBoundary() {
        let snapshot = SurgeFixtures.snapshot
        let generatedAt = snapshot.generatedAt

        #expect(snapshot.isStale(now: generatedAt) == false)
        #expect(snapshot.isStale(now: generatedAt.addingTimeInterval(300)) == false)
        #expect(snapshot.isStale(now: generatedAt.addingTimeInterval(301)))
    }

    @Test func dailySpendTotalsPerProvider() {
        let point = DailySpendPoint(
            date: SurgeFixtures.referenceDate,
            spendByProvider: ["anthropic": 1.0, "deepseek": 0.5]
        )

        #expect(abs(point.totalUSD - 1.5) < 0.000_001)
        #expect(point.spend(for: .anthropic) == 1.0)
        #expect(point.spend(for: .openrouter) == 0)
    }

    @Test func anUnavailableReasonSurvivesTheSnapshotRoundTrip() throws {
        let balance = AccountBalance(
            provider: "deepseek",
            amountUSD: nil,
            lastPolledAt: SurgeFixtures.referenceDate,
            unavailableReason: BalanceUnavailableReason(.keyRejected, statusCode: 401)
        )
        let data = try JSONEncoder().encode(balance)
        let decoded = try JSONDecoder().decode(AccountBalance.self, from: data)

        #expect(decoded == balance)
        #expect(decoded.unavailableReason?.category == .keyRejected)
        #expect(decoded.unavailableReason?.statusCode == 401)
        #expect(decoded.isAvailable == false)
    }

    @Test func aSnapshotFromBeforeReasonsStillDecodes() throws {
        let legacy = """
            {
              "provider": "anthropic",
              "amountUSD": null,
              "lastPolledAt": 761000000,
              "kind": "wallet"
            }
            """
        let balance = try JSONDecoder().decode(AccountBalance.self, from: Data(legacy.utf8))

        #expect(balance.provider == "anthropic")
        #expect(balance.unavailableReason == nil)
        #expect(balance.amountUSD == nil)
    }

    @Test func everyReasonCategoryHasItsOwnPlainEnglishText() {
        let texts = BalanceUnavailableReason.Category.allCases.map { BalanceUnavailableReason($0).text }

        #expect(texts.count == Set(texts).count)
        #expect(texts.allSatisfy { $0.isEmpty == false })
        #expect(BalanceUnavailableReason(.keyRejected).text == "Key rejected")
        #expect(BalanceUnavailableReason(.unreachable).text == "Could not reach provider")
        #expect(BalanceUnavailableReason(.unexpectedResponse).text == "Unexpected response")
    }
}
