import SurgeCore
import SwiftUI
import Testing

@testable import SurgeUI

struct ContrastTests {
    @Test func everyTokenPairMeetsItsFloor() {
        let pairs = SurgeContrastPairs.all
        #expect(!pairs.isEmpty)

        for pair in pairs {
            let ratio = pair.ratio
            #expect(ratio != nil, "\(pair.name) did not resolve")
            #expect(
                pair.passes,
                "\(pair.name) is \(ratio ?? 0):1, below \(pair.minimumRatio):1"
            )
        }
    }

    @Test func textPairsAreCheckedAtFourPointFiveToOne() throws {
        let textPairs = SurgeContrastPairs.textPairs
        #expect(textPairs.count == 14)
        #expect(textPairs.allSatisfy { $0.kind == .text })
        #expect(textPairs.allSatisfy { $0.minimumRatio == 4.5 })
    }

    @Test func graphicsAreCheckedAtThreeToOne() throws {
        let graphics = SurgeContrastPairs.graphicPairs
        #expect(graphics.allSatisfy { $0.kind == .graphic })
        #expect(graphics.allSatisfy { $0.minimumRatio == 3 })
    }

    @Test func computedRatiosMatchTheDesignSystem() throws {
        #expect(try ratio(SurgeInk.primary(), on: SurgeColors.card) == 18.08)
        #expect(try ratio(SurgeInk.secondary(.standard), on: SurgeColors.card) == 9.23)
        #expect(try ratio(SurgeInk.tertiary(.standard), on: SurgeColors.card) == 6.13)
        #expect(try ratio(SurgeInk.tertiary(.standard), on: SurgeColors.tile) == 5.6)
        #expect(try ratio(SurgeColors.violet, on: SurgeColors.card) == 4.94)
        #expect(try ratio(SurgeColors.alert, on: SurgeColors.card) == 7.23)
        #expect(try ratio(SurgeColors.caution, on: SurgeColors.card) == 9.57)
    }

    @Test func increasedContrastLiftsEveryTextToken() throws {
        for surface in [SurgeColors.card, SurgeColors.tile] {
            let standard = try ratio(SurgeInk.secondary(.standard), on: surface)
            let increased = try ratio(SurgeInk.secondary(.increased), on: surface)
            #expect(increased > standard)

            let tertiaryStandard = try ratio(SurgeInk.tertiary(.standard), on: surface)
            let tertiaryIncreased = try ratio(SurgeInk.tertiary(.increased), on: surface)
            #expect(tertiaryIncreased > tertiaryStandard)
        }
    }

    @Test func compositingFollowsSourceOver() throws {
        let white = try #require(SurgeSRGB(Color.white))
        let card = try #require(SurgeSRGB(SurgeColors.card))
        let translucent = SurgeSRGB(red: white.red, green: white.green, blue: white.blue, alpha: 0.5)
        let over = translucent.composited(over: card)

        #expect(abs(over.red - (0.5 + 0.5 * card.red)) < 0.000_1)
        #expect(abs(white.composited(over: card).red - 1) < 0.000_1)
        #expect(over.alpha == 1)
    }

    @Test func contrastMathsIsSymmetricAndBounded() throws {
        let white = try #require(SurgeSRGB(Color.white))
        let black = try #require(SurgeSRGB(Color.black))

        #expect(abs(white.contrastRatio(with: black) - 21) < 0.01)
        #expect(abs(white.contrastRatio(with: white) - 1) < 0.000_1)
        #expect(
            abs(white.contrastRatio(with: black) - black.contrastRatio(with: white)) < 0.000_1
        )
    }

    private func ratio(_ foreground: Color, on background: Color) throws -> Double {
        let pair = SurgeContrastPair(
            name: "test",
            foreground: foreground,
            background: background,
            kind: .text
        )
        let value = try #require(pair.ratio)
        return (value * 100).rounded() / 100
    }
}
