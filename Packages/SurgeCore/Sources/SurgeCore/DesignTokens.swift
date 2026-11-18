import CoreText
import SwiftUI

public enum SurgeColors {
    public static let card = Color(hex: 0x161617)
    public static let tile = Color(hex: 0x262627)
    public static let lime = Color(hex: 0xDFE301)
    public static let green = Color(hex: 0x03C37B)
    public static let magenta = Color(hex: 0xFF79FB)
    public static let violet = Color(hex: 0xA86BD6)
    public static let alert = Color(hex: 0xFF7D6B)
    public static let caution = Color(hex: 0xFFAA4F)
    public static let hairline = Color.white.opacity(0.15)
    public static let hairlineIncreasedContrast = Color.white.opacity(0.35)
}

extension Color {
    public static var surgeCard: Color { SurgeColors.card }
    public static var surgeAlert: Color { SurgeColors.alert }
    public static var surgeCaution: Color { SurgeColors.caution }
}

extension Provider {
    public var color: Color {
        switch self {
        case .anthropic: SurgeColors.lime
        case .deepseek: SurgeColors.green
        case .openrouter: SurgeColors.magenta
        case .other: SurgeColors.violet
        }
    }
}

public enum SurgeInk {
    public static func primary() -> Color {
        .white
    }

    public static func secondary(_ contrast: ColorSchemeContrast = .standard) -> Color {
        .white.opacity(contrast == .increased ? 0.85 : 0.70)
    }

    public static func tertiary(_ contrast: ColorSchemeContrast = .standard) -> Color {
        .white.opacity(contrast == .increased ? 0.75 : 0.55)
    }
}

public enum SurgeWeight: CGFloat, CaseIterable, Sendable {
    case light = 300
    case clear = 350
    case regular = 400
    case medium = 500
    case semibold = 600

    /// The closest standard SwiftUI weight. Clear 350 has no standard weight.
    public var standardWeight: Font.Weight {
        switch self {
        case .light: .light
        case .clear: .regular
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}

public enum SurgeFontRole: Sendable {
    case sans
    case mono
}

public enum SurgeTypography {
    public static let sansFamilyName = "Geist"
    public static let monoFamilyName = "Fira Code"
    public static let minimumSize: CGFloat = 10
    public static let widgetMinimumSize: CGFloat = 11

    public static func sans(_ size: CGFloat, weight: SurgeWeight = .regular) -> Font {
        resolvedFont(
            family: sansFamilyName,
            role: .sans,
            size: size,
            weight: weight,
            isAvailable: isFamilyAvailable(sansFamilyName)
        )
    }

    public static func mono(_ size: CGFloat, weight: SurgeWeight = .regular) -> Font {
        resolvedFont(
            family: monoFamilyName,
            role: .mono,
            size: size,
            weight: weight,
            isAvailable: isFamilyAvailable(monoFamilyName)
        )
    }

    /// Picks the system font when the family is missing, otherwise the custom family with a variable weight.
    public static func resolvedFont(
        family: String,
        role: SurgeFontRole,
        size: CGFloat,
        weight: SurgeWeight,
        isAvailable: Bool
    ) -> Font {
        guard isAvailable else {
            switch role {
            case .sans:
                return .system(size: size, weight: weight.standardWeight)
            case .mono:
                return .system(size: size, weight: weight.standardWeight, design: .monospaced)
            }
        }
        if weight == .clear, let variable = variableFont(family: family, size: size, weight: weight.rawValue) {
            return variable
        }
        return .custom(family, fixedSize: size).weight(weight.standardWeight)
    }

    public static func displayTracking(forSize size: CGFloat) -> CGFloat {
        -0.03 * size
    }

    public static let readoutXL = sans(40, weight: .light)
    public static let readoutL = sans(28, weight: .light)
    public static let readoutM = sans(22, weight: .light)
    public static let title = sans(15, weight: .clear)
    public static let body = sans(13)
    public static let meta = sans(11)
    public static let label = sans(10)
    public static let widgetMeta = sans(11)
    public static let path = mono(11)

    private static let weightAxisIdentifier = 0x7767_6874  // 'wght'

    private static func isFamilyAvailable(_ family: String) -> Bool {
        let font = CTFontCreateWithName(family as CFString, 13, nil)
        let resolvedFamily = CTFontCopyFamilyName(font) as String
        return resolvedFamily.caseInsensitiveCompare(family) == .orderedSame
    }

    private static func variableFont(family: String, size: CGFloat, weight: CGFloat) -> Font? {
        let base = CTFontCreateWithName(family as CFString, size, nil)
        let resolvedFamily = CTFontCopyFamilyName(base) as String
        guard resolvedFamily.caseInsensitiveCompare(family) == .orderedSame else { return nil }
        guard
            let axes = CTFontCopyVariationAxes(base) as? [[String: Any]],
            axes.contains(where: { axis in
                let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber
                return identifier?.intValue == weightAxisIdentifier
            })
        else {
            return nil
        }

        let variation = [NSNumber(value: weightAxisIdentifier): NSNumber(value: Double(weight))]
        let attributes = [kCTFontVariationAttribute: variation] as CFDictionary
        let baseDescriptor = CTFontDescriptorCreateWithNameAndSize(family as CFString, size)
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(baseDescriptor, attributes)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

public enum SurgeSpacing {
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let cardGap: CGFloat = 6
    public static let cardPadding: CGFloat = 14
    public static let section: CGFloat = 12
}

public enum SurgeRadius {
    public static let popover: CGFloat = 22
    public static let card: CGFloat = 16
    public static let tile: CGFloat = 12
    public static let row: CGFloat = 10
}

public enum SurgeSize {
    public static let popoverWidth: CGFloat = 360
    public static let popoverMaxHeight: CGFloat = 720
    public static let pillTabHeight: CGFloat = 28
    public static let chipHeight: CGFloat = 24
    public static let menuBarItemHeight: CGFloat = 22
    public static let fuseRowHeight: CGFloat = 6
    public static let fuseHeroHeight: CGFloat = 10
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
