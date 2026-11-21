import Foundation
import SurgeCore
import Testing

@testable import SurgeUI

struct FusePresentationTests {
    @Test func normalFillKeepsThePercentageLabel() {
        let presentation = FusePresentation(
            agent: UITestFixtures.agent(contextTokens: 84_000),
            now: UITestFixtures.now
        )

        #expect(presentation.state == .normal)
        #expect(presentation.level == .normal)
        #expect(abs((presentation.fillRatio ?? 0) - 0.42) < 0.000_001)
        #expect(presentation.label == "42%")
        #expect(presentation.contextLabel == "42%")
        #expect(presentation.contextClause == "Context 42 percent")
        #expect(presentation.isTripped == false)
    }

    @Test func highFillStartsAtSeventyPercent() {
        #expect(
            FusePresentation(agent: UITestFixtures.agent(contextTokens: 139_800), now: UITestFixtures.now).state
                == .normal)

        let presentation = FusePresentation(
            agent: UITestFixtures.agent(contextTokens: 140_000),
            now: UITestFixtures.now
        )

        #expect(presentation.state == .high)
        #expect(presentation.label == "70% · High")
        #expect(presentation.contextLabel == "70% · High")
        #expect(presentation.accessibilityLabel == "Context 70 percent of 200 thousand tokens, high")
    }

    @Test func nearLimitFillStartsAtNinetyPercent() {
        let high = FusePresentation(agent: UITestFixtures.agent(contextTokens: 179_800), now: UITestFixtures.now)
        #expect(high.state == .high)

        let nearLimit = FusePresentation(agent: UITestFixtures.agent(contextTokens: 180_000), now: UITestFixtures.now)
        #expect(nearLimit.state == .nearLimit)
        #expect(nearLimit.label == "90% · Near limit")
        #expect(nearLimit.contextClause == "Context 90 percent, near limit")
    }

    @Test func stalledAgentIsTrippedAndKeepsItsFill() throws {
        let agent = UITestFixtures.agent(
            status: .stalled(since: UITestFixtures.now.addingTimeInterval(-194)),
            contextTokens: 150_000
        )
        let presentation = FusePresentation(agent: agent, now: UITestFixtures.now)

        #expect(presentation.state == .tripped)
        #expect(presentation.isTripped)
        #expect(presentation.fillRatio == 0.75)
        #expect(presentation.label == "Stalled 3m 14s")
        #expect(presentation.contextLabel == "75% · High")
        #expect(presentation.contextClause == "Context 75 percent, high")
    }

    @Test func idleAgentShowsTheIdleWordAndDuration() {
        let agent = UITestFixtures.agent(
            status: .idle(since: UITestFixtures.now.addingTimeInterval(-240)),
            contextTokens: 24_000
        )
        let presentation = FusePresentation(agent: agent, now: UITestFixtures.now)

        #expect(presentation.state == .idle)
        #expect(presentation.level == .normal)
        #expect(presentation.label == "12% · Idle 4m")
        #expect(presentation.contextLabel == "12%")
    }

    @Test func idleAgentPastTheThresholdStillShowsTheContextWord() {
        let agent = UITestFixtures.agent(
            status: .idle(since: UITestFixtures.now.addingTimeInterval(-240)),
            contextTokens: 186_000
        )
        let presentation = FusePresentation(agent: agent, now: UITestFixtures.now)

        #expect(presentation.state == .idle)
        #expect(presentation.level == .nearLimit)
        #expect(presentation.label == "93% · Near limit")
        #expect(presentation.contextLabel == "93% · Near limit")
    }

    @Test func noSignalHasNoFill() {
        let presentation = FusePresentation(
            agent: UITestFixtures.agent(status: .noSignal, contextTokens: 90_000),
            now: UITestFixtures.now
        )

        #expect(presentation.state == .unknown)
        #expect(presentation.level == nil)
        #expect(presentation.fillRatio == nil)
        #expect(presentation.label == "No data")
        #expect(presentation.contextLabel == "No data")
        #expect(presentation.contextClause == "Context unavailable")
        #expect(presentation.accessibilityLabel == "Context unavailable, no data")
    }

    @Test func zeroWindowIsUnknownEvenWhileWorking() {
        let presentation = FusePresentation(
            agent: UITestFixtures.agent(status: .working, contextTokens: 0, window: 0),
            now: UITestFixtures.now
        )

        #expect(presentation.state == .unknown)
        #expect(presentation.fillRatio == nil)
    }

    @Test func windowIsSpelledForVoiceOver() {
        #expect(FusePresentation.spelledTokenWindow(200_000) == "200 thousand")
        #expect(FusePresentation.spelledTokenWindow(128_000) == "128 thousand")
        #expect(FusePresentation.spelledTokenWindow(1_000_000) == "1 million")
        #expect(FusePresentation.spelledTokenWindow(1_500_000) == "1.5 million")
        #expect(FusePresentation.spelledTokenWindow(200_500) == "200.5 thousand")
        #expect(FusePresentation.spelledTokenWindow(500) == "500")
    }

    @Test func fillIsClampedToOneHundredPercent() {
        let presentation = FusePresentation(
            agent: UITestFixtures.agent(contextTokens: 400_000),
            now: UITestFixtures.now
        )

        #expect(presentation.fillRatio == 1)
        #expect(presentation.label == "100% · Near limit")
    }

    @Test func theHatchIsOnlyDrawnForAStall() {
        let cases: [(AgentStatus, Bool)] = [
            (.working, false),
            (.waitingForYou, false),
            (.stalled(since: UITestFixtures.now.addingTimeInterval(-194)), true),
            (.compacting, false),
            (.idle(since: UITestFixtures.now.addingTimeInterval(-240)), false),
            (.done, false),
            (.noSignal, false),
        ]

        for (status, tripsTheFuse) in cases {
            let presentation = FusePresentation(
                agent: UITestFixtures.agent(status: status, contextTokens: 150_000),
                now: UITestFixtures.now
            )

            #expect(presentation.isTripped == tripsTheFuse, "\(status)")
        }
    }

    @Test func recoveryClearsLeftToRight() {
        #expect(FusePresentation.hatchClear(reduceMotion: false) == .leftToRight)
    }

    @Test func reduceMotionMakesTheClearACrossFade() {
        #expect(FusePresentation.hatchClear(reduceMotion: true) == .crossFade)
    }
}
