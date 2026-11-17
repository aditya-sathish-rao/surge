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

public enum SurgeTypography {
    public static let sansFamilyName = "Inter Tight"
    public static let monoFamilyName = "Fira Code"
    public static let minimumSize: CGFloat = 10
    public static let widgetMinimumSize: CGFloat = 11

    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(sansFamilyName, fixedSize: size).weight(weight)
    }

    public static func displayTracking(forSize size: CGFloat) -> CGFloat {
        -0.03 * size
    }

    public static let readoutXL = sans(40, weight: .light)
    public static let readoutL = sans(28, weight: .light)
    public static let readoutM = sans(22, weight: .light)
    public static let title = sans(15)
    public static let body = sans(13)
    public static let meta = sans(11)
    public static let label = sans(10)
    public static let widgetMeta = sans(11)
    public static let path = Font.custom(monoFamilyName, fixedSize: 11)
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
