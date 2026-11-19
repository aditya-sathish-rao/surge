import SurgeCore
import SwiftUI

/// The Fuse: the capsule context meter shared by every surface.
public enum FuseSize: Sendable, Equatable {
    case row
    case hero

    var height: CGFloat {
        switch self {
        case .row: SurgeSize.fuseRowHeight
        case .hero: SurgeSize.fuseHeroHeight
        }
    }
}

/// A real `Gauge` with a custom style. The visible label always sits beside it, read from the
/// presentation, so no surface can draw the meter without one.
public struct Fuse: View {
    private let presentation: FusePresentation
    private let size: FuseSize
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }
    private var reduceMotion: Bool { SurgeAccessibility.reduceMotion(appearance, system: systemReduceMotion) }

    public init(_ presentation: FusePresentation, size: FuseSize = .row) {
        self.presentation = presentation
        self.size = size
    }

    public var body: some View {
        Gauge(value: presentation.fillRatio ?? 0, in: 0...1) {
            EmptyView()
        }
        .gaugeStyle(
            FuseGaugeStyle(
                presentation: presentation,
                height: size.height,
                increasedContrast: contrastLevel == .increased,
                reduceMotion: reduceMotion
            )
        )
        .frame(height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

struct FuseGaugeStyle: GaugeStyle {
    let presentation: FusePresentation
    let height: CGFloat
    let increasedContrast: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            let ratio = min(max(presentation.fillRatio ?? 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(SurgeUIStyle.fuseTrack)
                fill(width: width, ratio: ratio)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: SurgeUIStyle.fuseAnimationDuration),
                        value: ratio
                    )
                notches(width: width, height: height)
            }
            .frame(width: width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay {
            if increasedContrast {
                Capsule().strokeBorder(
                    SurgeColors.hairlineIncreasedContrast, lineWidth: SurgeUIStyle.contrastOutlineWidth)
            }
        }
    }

    @ViewBuilder
    private func fill(width: CGFloat, ratio: Double) -> some View {
        if presentation.isTripped {
            HatchPattern(color: SurgeColors.alert)
                .frame(width: width * ratio, height: height)
                .clipShape(Capsule())
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: SurgeUIStyle.fuseAnimationDuration),
                    value: presentation.isTripped
                )
        } else {
            Capsule()
                .fill(fillColor)
                .frame(width: width * ratio, height: height)
        }
    }

    /// Status owns orange and coral, and a healthy agent is drawn in white.
    private var fillColor: Color {
        switch presentation.level {
        case .high: SurgeColors.caution
        case .nearLimit: SurgeColors.alert
        case .normal, nil: SurgeInk.primary()
        }
    }

    private func notches(width: CGFloat, height: CGFloat) -> some View {
        ForEach(SurgeUIStyle.notchPositions, id: \.self) { position in
            Rectangle()
                .fill(SurgeUIStyle.notch)
                .frame(width: SurgeUIStyle.notchWidth, height: height)
                .offset(x: width * position)
        }
    }
}

/// A 45 degree stripe pattern in the status hue. The pattern is the signal, so a stalled agent
/// still reads in grayscale and under vibrant rendering.
struct HatchPattern: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(color.opacity(SurgeUIStyle.hatchWashOpacity))
            )
            var start = -size.height
            while start < size.width {
                var path = Path()
                path.move(to: CGPoint(x: start, y: size.height))
                path.addLine(to: CGPoint(x: start + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: SurgeUIStyle.hatchLineWidth)
                start += SurgeUIStyle.hatchSpacing
            }
        }
        .accessibilityHidden(true)
    }
}
