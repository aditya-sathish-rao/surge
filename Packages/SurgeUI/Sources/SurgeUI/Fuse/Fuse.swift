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
                if !presentation.isTripped {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: width * ratio, height: height)
                        .animation(fillAnimation, value: ratio)
                        .transition(.asymmetric(insertion: fillReveal, removal: .opacity))
                }
                if presentation.isTripped {
                    HatchPattern(color: SurgeColors.alert)
                        .frame(width: width * ratio, height: height)
                        .clipShape(Capsule())
                        .transition(.asymmetric(insertion: .opacity, removal: hatchClear))
                }
                notches(width: width, height: height)
            }
            .animation(tripOrClear, value: presentation.isTripped)
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

    /// The fill eases to a new value only while it is drawn and motion is allowed. It never moves
    /// under a hatch, and it does not travel at all when Reduce Motion is on.
    private var fillAnimation: Animation? {
        guard presentation.fillAnimates, !reduceMotion else { return nil }
        return .easeOut(duration: SurgeUIStyle.fuseAnimationDuration)
    }

    /// The Fuse's one choreographed moment. The value-driven animation means a Fuse that first
    /// appears, or a widget that reloads, arrives whole instead of replaying the trip.
    private var tripOrClear: Animation {
        presentation.isTripped
            ? FuseCurve.trip(reduceMotion: reduceMotion)
            : FuseCurve.clear(reduceMotion: reduceMotion)
    }

    /// On recovery the hatch clears from its left edge and the fill arrives behind it, so both
    /// sides of the moment use the same wipe from opposite ends and meet in the middle.
    private var fillReveal: AnyTransition { wipe(anchor: .leading) }
    private var hatchClear: AnyTransition { wipe(anchor: .trailing) }

    private func wipe(anchor: UnitPoint) -> AnyTransition {
        switch FusePresentation.hatchClear(reduceMotion: reduceMotion) {
        case .leftToRight:
            .modifier(
                active: FuseWipe(progress: 0, anchor: anchor),
                identity: FuseWipe(progress: 1, anchor: anchor)
            )
        case .crossFade:
            .opacity
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

/// The curves of the Fuse's one choreographed moment. The presentation decides which motion
/// plays; these are the timings the design system gives that moment.
private enum FuseCurve {
    /// Reduce Motion dissolves the trip instead of moving it, briefly.
    static let crossFadeDuration: TimeInterval = 0.2
    /// On recovery the hatch clears and the fill resumes together over one spring.
    static let clearDuration: TimeInterval = 0.4
    static let clearBounce: Double = 0.1

    static func trip(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: crossFadeDuration)
            : .easeOut(duration: SurgeUIStyle.fuseAnimationDuration)
    }

    static func clear(reduceMotion: Bool) -> Animation {
        switch FusePresentation.hatchClear(reduceMotion: reduceMotion) {
        case .leftToRight: .spring(duration: clearDuration, bounce: clearBounce)
        case .crossFade: .easeInOut(duration: crossFadeDuration)
        }
    }
}

/// Masks a view to a part of itself, so the hatch can leave and the fill can arrive on the same
/// moving edge. `progress` runs from 1 to 0 as the hatch clears and 0 to 1 as the fill reveals.
struct FuseWipe: ViewModifier, Animatable {
    var progress: CGFloat
    var anchor: UnitPoint

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            Rectangle().scaleEffect(x: max(progress, 0), anchor: anchor)
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
