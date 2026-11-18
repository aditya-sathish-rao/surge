import SwiftUI

/// Accessibility settings a preview or an offscreen render check can force.
///
/// SwiftUI exposes Increase Contrast and Reduce Motion as read-only environment values, so the
/// Xcode canvas toggles them for the user. Views read this optional override first so the same
/// states can be rendered and checked without changing the Mac's settings.
public struct SurgeAppearance: Sendable, Equatable {
    public var contrast: ColorSchemeContrast
    public var reduceMotion: Bool

    public init(contrast: ColorSchemeContrast = .standard, reduceMotion: Bool = false) {
        self.contrast = contrast
        self.reduceMotion = reduceMotion
    }
}

private struct SurgeAppearanceKey: EnvironmentKey {
    static let defaultValue: SurgeAppearance? = nil
}

extension EnvironmentValues {
    public var surgeAppearance: SurgeAppearance? {
        get { self[SurgeAppearanceKey.self] }
        set { self[SurgeAppearanceKey.self] = newValue }
    }
}

extension View {
    public func surgeAppearance(_ appearance: SurgeAppearance) -> some View {
        environment(\.surgeAppearance, appearance)
    }
}

enum SurgeAccessibility {
    static func contrast(_ appearance: SurgeAppearance?, system: ColorSchemeContrast) -> ColorSchemeContrast {
        appearance?.contrast ?? system
    }

    static func reduceMotion(_ appearance: SurgeAppearance?, system: Bool) -> Bool {
        appearance?.reduceMotion ?? system
    }
}
