import SurgeCore
import SwiftUI
import Testing

struct DesignTokensTests {
    @Test func missingSansFamilyFallsBackToSystemFont() {
        let font = SurgeTypography.resolvedFont(
            family: SurgeTypography.sansFamilyName,
            role: .sans,
            size: 13,
            weight: .regular,
            isAvailable: false
        )

        #expect(font == .system(size: 13, weight: .regular))
    }

    @Test func missingMonoFamilyFallsBackToSystemMonospacedFont() {
        let font = SurgeTypography.resolvedFont(
            family: SurgeTypography.monoFamilyName,
            role: .mono,
            size: 11,
            weight: .regular,
            isAvailable: false
        )

        #expect(font == .system(size: 11, weight: .regular, design: .monospaced))
    }

    @Test func availableSansFamilyUsesTheCustomFace() {
        let font = SurgeTypography.resolvedFont(
            family: SurgeTypography.sansFamilyName,
            role: .sans,
            size: 13,
            weight: .regular,
            isAvailable: true
        )

        #expect(font == .custom(SurgeTypography.sansFamilyName, fixedSize: 13).weight(.regular))
    }

    @Test func clearWeightFallsBackToNearestStandardWeight() {
        #expect(SurgeWeight.clear.rawValue == 350)
        #expect(SurgeWeight.clear.standardWeight == .regular)

        let font = SurgeTypography.resolvedFont(
            family: "Surge Missing Variable Family",
            role: .sans,
            size: 15,
            weight: .clear,
            isAvailable: true
        )

        #expect(font == .custom("Surge Missing Variable Family", fixedSize: 15).weight(.regular))
    }

    @Test func fontFamiliesAreGeistAndFiraCode() {
        #expect(SurgeTypography.sansFamilyName == "Geist")
        #expect(SurgeTypography.monoFamilyName == "Fira Code")
    }

    @Test func designWeightsUseTheDocumentedValues() {
        #expect(SurgeWeight.light.rawValue == 300)
        #expect(SurgeWeight.clear.rawValue == 350)
        #expect(SurgeWeight.regular.rawValue == 400)
        #expect(SurgeWeight.medium.rawValue == 500)
        #expect(SurgeWeight.semibold.rawValue == 600)
    }
}
