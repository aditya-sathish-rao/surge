import Charts
import SurgeCore
import SwiftUI

/// Throughput over the last 30 minutes: white line, soft fill, endpoint dot, zero baseline and a
/// trailing y-axis. Every chart carries its headline and summary above it.
public struct ThroughputChart: View {
    private let samples: [ThroughputSample]
    private let summary: ThroughputSummary
    private let isWidget: Bool
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(samples: [ThroughputSample], isWidget: Bool = false) {
        self.samples = samples
        summary = ThroughputSummary(samples: samples)
        self.isWidget = isWidget
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            SurgeSectionLabel("Throughput · 30 min", isWidget: isWidget)
            Text(summary.headline)
                .font(isWidget ? SurgeUIFont.chartHeadlineCompact : SurgeUIFont.chartHeadline)
                .foregroundStyle(SurgeInk.primary())
                .monospacedDigit()
            Text(summary.caption)
                .font(SurgeUIFont.chartCaption)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.date),
                    y: .value("Tokens per second", sample.tokensPerSecond)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [SurgeInk.primary().opacity(0.20), SurgeInk.primary().opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("Tokens per second", sample.tokensPerSecond)
                )
                .foregroundStyle(SurgeInk.primary())
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            if let last = samples.last {
                PointMark(
                    x: .value("Time", last.date),
                    y: .value("Tokens per second", last.tokensPerSecond)
                )
                .foregroundStyle(SurgeInk.primary())
                .symbolSize(SurgeUIStyle.chartPointSize)
            }
        }
        .chartYScale(domain: 0...max(1, (samples.map(\.tokensPerSecond).max() ?? 0) * 1.15))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(SurgeInk.primary().opacity(SurgeUIStyle.chartGridOpacity))
                AxisValueLabel()
                    .font(isWidget ? SurgeUIFont.chartAxisWidget : SurgeUIFont.chartAxis)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisTick().foregroundStyle(SurgeInk.primary().opacity(SurgeUIStyle.chartTickOpacity))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(isWidget ? SurgeUIFont.chartAxisWidget : SurgeUIFont.chartAxis)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            }
        }
        .frame(height: SurgeUIStyle.throughputChartHeight)
        .accessibilityLabel("Throughput over the last 30 minutes")
        .accessibilityChartDescriptor(ThroughputChartDescriptor(samples: samples))
    }
}
