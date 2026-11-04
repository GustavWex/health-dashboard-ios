import Foundation

public struct LoadResult: Sendable {
    public let todayActive: Double?
    public let acwr: Double?
    public let band: String
    public let typicalWeekdays: [Int]     // Calendar weekday numbers, Monday first
    public let cadenceDays: Int?          // set instead of weekdays for an interval rhythm, e.g. 2 = every other day
    public let sessionsPerWeek: Double
    public let lastStrength: Date?
    public let recent: [WorkoutSummary]
}

public enum LoadEngine {
    /// Acute:chronic workload ratio, mean of the last 7 days over mean of the last 28, ending yesterday.
    /// Bands follow Gabbett (2016), "The training-injury prevention paradox", Br J Sports Med 50:273-280:
    /// 0.8 to 1.3 is the sweet spot, above 1.5 the danger zone.
    /// Computed on active energy, a rough proxy that undercounts heavy lifting. Phase 3 switches to TRIMP.
    public static func evaluate(_ s: HealthSnapshot, day: Date) -> LoadResult {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)!
        let acute = Stats.mean(s.activeEnergy.recent(days: 7, from: yesterday).map(\.value))
        let chronicVals = s.activeEnergy.recent(days: 28, from: yesterday).map(\.value)
        let chronic = Stats.mean(chronicVals)

        var acwr: Double?
        if let a = acute, let c = chronic, c > 0, chronicVals.count >= 21 { acwr = a / c }

        let band: String
        switch acwr {
        case nil: band = "Needs 3 weeks of data"
        case let r? where r < 0.8: band = "Below usual"
        case let r? where r <= 1.3: band = "Steady"
        case let r? where r <= 1.5: band = "Building fast"
        default: band = "Spike"
        }

        // Derived schedule (Omnio): weekdays with a strength session in at least 4 of the last 8 weeks.
        // An every-other-day rhythm walks through all weekdays and would light up most of them, so when more
        // than 3 weekdays qualify, describe the rhythm by its typical gap instead.
        let since = cal.date(byAdding: .day, value: -56, to: day)!
        let strength = s.workouts.filter { $0.isStrength && $0.start >= since }
        let counts = Dictionary(grouping: strength) { cal.component(.weekday, from: $0.start) }.mapValues(\.count)
        var typical = counts.filter { $0.value >= 4 }.keys.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        var cadence: Int?
        if typical.count > 3 {
            let days = Set(strength.map { cal.startOfDay(for: $0.start) }).sorted()
            let gaps = zip(days.dropFirst(), days).compactMap { cal.dateComponents([.day], from: $1, to: $0).day }
            if let median = Stats.percentile(gaps.map(Double.init), 0.5), median >= 1.5 {
                cadence = Int(median.rounded())
            }
            typical = []
        }

        return LoadResult(
            todayActive: s.activeEnergy.value(on: day),
            acwr: acwr,
            band: band,
            typicalWeekdays: typical,
            cadenceDays: cadence,
            sessionsPerWeek: Double(strength.count) / 8,
            lastStrength: strength.map(\.start).max(),
            recent: Array(s.workouts.prefix(5))
        )
    }
}
