import AppKit
import SurgeCore
import SwiftUI

/// A colour resolved to sRGB components, so contrast can be computed from the token values
/// themselves instead of from a copy of the hex numbers.
public struct SurgeSRGB: Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Resolves a SwiftUI colour to sRGB. Returns nil when the colour cannot be converted,
    /// which keeps a platform conversion failure out of the contrast maths.
    public init?(_ color: Color) {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }

    /// Source-over compositing of this colour onto an opaque background.
    public func composited(over background: SurgeSRGB) -> SurgeSRGB {
        SurgeSRGB(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha),
            alpha: 1
        )
    }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// WCAG 2.x contrast ratio, from 1:1 to 21:1.
    public func contrastRatio(with other: SurgeSRGB) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func linear(_ component: Double) -> Double {
        let clamped = min(max(component, 0), 1)
        return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
    }
}

/// One foreground and background pair the design system promises a minimum contrast for.
public struct SurgeContrastPair: Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// Text the user reads, which must reach 4.5:1.
        case text
        /// A status or provider graphic, which must reach 3:1.
        case graphic
    }

    public let name: String
    public let foreground: Color
    public let background: Color
    public let kind: Kind

    public init(name: String, foreground: Color, background: Color, kind: Kind) {
        self.name = name
        self.foreground = foreground
        self.background = background
        self.kind = kind
    }

    public var minimumRatio: Double {
        kind == .text ? SurgeContrastStandard.textMinimum : SurgeContrastStandard.graphicMinimum
    }

    /// The computed ratio, or nil when either colour does not resolve on this platform.
    public var ratio: Double? {
        guard let surface = SurgeSRGB(background), let ink = SurgeSRGB(foreground) else { return nil }
        return ink.composited(over: surface).contrastRatio(with: surface)
    }

    public var passes: Bool {
        guard let ratio else { return false }
        return ratio >= minimumRatio
    }
}

public enum SurgeContrastStandard {
    /// The accessibility floor for every text token.
    public static let textMinimum = 4.5
    /// The accessibility floor for every status and provider graphic.
    public static let graphicMinimum = 3.0
}

/// The colour pairs Surge ships against. Every pair is checked in the test suite.
public enum SurgeContrastPairs {
    public static var all: [SurgeContrastPair] {
        textPairs + graphicPairs
    }

    static var textPairs: [SurgeContrastPair] {
        let inks: [(String, Color)] = [
            ("primary text", SurgeInk.primary()),
            ("secondary text", SurgeInk.secondary(.standard)),
            ("secondary text, increased contrast", SurgeInk.secondary(.increased)),
            ("tertiary text", SurgeInk.tertiary(.standard)),
            ("tertiary text, increased contrast", SurgeInk.tertiary(.increased)),
            ("caution status text", SurgeColors.caution),
            ("alert status text", SurgeColors.alert),
        ]
        return onBothSurfaces(inks, kind: .text)
    }

    static var graphicPairs: [SurgeContrastPair] {
        let hues: [(String, Color)] = [
            ("lime provider dot", SurgeColors.lime),
            ("green provider dot", SurgeColors.green),
            ("magenta provider dot", SurgeColors.magenta),
            ("violet provider dot", SurgeColors.violet),
            ("caution status graphic", SurgeColors.caution),
            ("alert status graphic", SurgeColors.alert),
        ]
        return onBothSurfaces(hues, kind: .graphic) + [
            SurgeContrastPair(
                name: "increased contrast hairline on card",
                foreground: SurgeColors.hairlineIncreasedContrast,
                background: SurgeColors.card,
                kind: .graphic
            )
        ]
    }

    private static func onBothSurfaces(
        _ colors: [(String, Color)],
        kind: SurgeContrastPair.Kind
    ) -> [SurgeContrastPair] {
        colors.flatMap { name, color in
            [
                SurgeContrastPair(
                    name: "\(name) on card",
                    foreground: color,
                    background: SurgeColors.card,
                    kind: kind
                ),
                SurgeContrastPair(
                    name: "\(name) on tile",
                    foreground: color,
                    background: SurgeColors.tile,
                    kind: kind
                ),
            ]
        }
    }
}
