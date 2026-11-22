import Foundation
import SurgeCore

/// The Large widget's 7-day spend chart as VoiceOver and Audio Graphs read it: the days the chart
/// draws, in the same order, with the words for each axis and the summary sentence.
///
/// The drawing belongs to `SurgeUI`. The numbers and words live here so they can be tested without
/// a rendered view.
public enum WidgetSpendChart {
    /// Must stay equal to the day count the Large widget draws the chart with
    /// (`DailySpendRange.sevenDays`).
    public static let dayCount = 7

    public static let title = "Daily spend · 7 days"
    public static let axisTitle = "Day"
    public static let valueAxisTitle = "Spend"
    public static let seriesName = "Spend"

    /// One day the chart draws: the word on the axis and the amount above it.
    public struct Day: Equatable, Sendable {
        public let label: String
        public let amountUSD: Double

        public init(label: String, amountUSD: Double) {
            self.label = label
            self.amountUSD = amountUSD
        }
    }

    /// The most recent `dayCount` days, oldest first, which is the order the bars are drawn in.
    public static func days(
        in points: [DailySpendPoint],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [Day] {
        points.sorted { $0.date < $1.date }.suffix(dayCount).map { point in
            Day(
                label: label(for: point.date, calendar: calendar, locale: locale),
                amountUSD: point.totalUSD
            )
        }
    }

    /// The day as its axis tick reads it, in the region's own month and day order, so the spoken
    /// axis matches the drawn one.
    public static func label(for date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style =
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
        return style.format(date)
    }

    /// What the whole chart says in one sentence: what it covers, today's amount and the total.
    public static func summary(_ days: [Day], source: CostSource) -> String {
        guard let today = days.last else { return "No daily spend recorded in the last \(dayCount) days." }
        let total = days.reduce(0) { $0 + $1.amountUSD }
        return "\(source.label) daily spend for the last \(dayCount) days. "
            + "\(SurgeFormatting.cost(today.amountUSD)) today, \(SurgeFormatting.cost(total)) in total."
    }

    /// The top of the value axis. Never zero, so Audio Graphs always has a range to read.
    public static func valueAxisMaximum(_ days: [Day]) -> Double {
        max(days.map(\.amountUSD).max() ?? 0, 1)
    }
}
