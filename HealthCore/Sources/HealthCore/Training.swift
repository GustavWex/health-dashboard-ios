import Foundation

public struct WorkoutHeartRate: Sendable {
    public let average: Double
    public let max: Double
    public let trimp: Double
    /// Minutes in zones 1 to 5 by heart rate reserve: 50-60, 60-70, 70-80, 80-90, 90+ %HRR. Below 50% is not counted.
    public let zoneMinutes: [Double]
}

/// Inputs every heart rate formula needs.
public struct HeartRateProfile: Sendable {
    public let rest: Double
    public let max: Double
    public let sex: Sex?

    public init(rest: Double, max: Double, sex: Sex?) {
        self.rest = rest
        self.max = max
        self.sex = sex
    }
}

public struct TrainingDay: Sendable {
    public let date: Date
    public let trimp: Double
    public let strain: Double?
    public let srpe: Double        // effort × minutes, 0 when no rating
}

public struct TrainingResult: Sendable {
    public let profile: HeartRateProfile?
    /// Day strain constant, calibrated on your own training days (see `calibrateTau`). nil until there's enough data.
    public let tau: Double?
    public let today: TrainingDay?
    public let fitness: Double?     // CTL, 42-day
    public let fatigue: Double?     // ATL, 7-day
    public var form: Double? { fitness.flatMap { f in fatigue.map { f - $0 } } }   // TSB
    public let days: [TrainingDay]  // oldest first
    public let strainTarget: ClosedRange<Double>?
}

public enum TrainingEngine {
    /// HRmax: Tanaka, Monahan and Seals (2001), "Age-predicted maximal heart rate revisited",
    /// J Am Coll Cardiol 37(1): 208 − 0.7·age. Replaced by the highest workout heart rate seen if that is higher.
    /// HRrest: mean resting heart rate over the last 30 days.
    public static func profile(_ s: HealthSnapshot, day: Date, observedMax: Double?) -> HeartRateProfile? {
        guard let rest = Stats.mean(s.restingHR.recent(days: 30, from: day).map(\.value)) else { return nil }
        let tanaka = s.profile.age(on: day).map { 208 - 0.7 * Double($0) }
        guard let hrMax = [tanaka, observedMax].compactMap({ $0 }).max(), hrMax > rest + 20 else { return nil }
        return HeartRateProfile(rest: rest, max: hrMax, sex: s.profile.sex)
    }

    /// Banister TRIMP: Σ Δt·HRr·a·e^(b·HRr), HRr = (HR − rest)/(max − rest), Δt in minutes.
    /// a = 0.64, b = 1.92 for men; 0.86 and 1.67 for women (male values when sex is unknown).
    /// Morton, Fitz-Clarke and Banister (1990), "Modeling human performance in running", J Appl Physiol 69(3).
    /// Each sample counts until the next one, capped at 2 minutes so gaps in the data don't inflate the load.
    public static func analyze(_ readings: [Reading], end: Date, profile p: HeartRateProfile) -> WorkoutHeartRate? {
        let r = readings.sorted { $0.date < $1.date }
        guard !r.isEmpty else { return nil }
        let (a, b) = p.sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        var trimp = 0.0
        var zones = [Double](repeating: 0, count: 5)
        for (i, x) in r.enumerated() {
            let next = i + 1 < r.count ? r[i + 1].date : end
            let minutes = min(2, max(0, next.timeIntervalSince(x.date) / 60))
            let hrr = min(1, max(0, (x.value - p.rest) / (p.max - p.rest)))
            trimp += minutes * hrr * a * exp(b * hrr)
            if hrr >= 0.5 { zones[min(4, Int((hrr - 0.5) * 10))] += minutes }
        }
        let values = r.map(\.value)
        return WorkoutHeartRate(average: Stats.mean(values) ?? 0, max: values.max() ?? 0, trimp: trimp, zoneMinutes: zones)
    }

    /// Adds heart rate analysis, effort and heart rate recovery to each workout.
    public static func enrich(_ workouts: [WorkoutSummary], heartRate: [Reading], effort: [Reading],
                              estimatedEffort: [Reading], hrRecovery: [Reading], snapshot s: HealthSnapshot,
                              day: Date) -> [WorkoutSummary] {
        let sorted = heartRate.sorted { $0.date < $1.date }
        // Binary search for the first sample of each workout, so matching stays fast on months of samples.
        func during(_ w: WorkoutSummary) -> ArraySlice<Reading> {
            var lo = 0, hi = sorted.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if sorted[mid].date < w.start { lo = mid + 1 } else { hi = mid }
            }
            var end = lo
            while end < sorted.count && sorted[end].date <= w.end { end += 1 }
            return sorted[lo..<end]
        }
        let observedMax = workouts.flatMap(during).map(\.value).max()
        let profile = profile(s, day: day, observedMax: observedMax)
        return workouts.map { w in
            var w = w
            if let p = profile { w.heartRate = analyze(Array(during(w)), end: w.end, profile: p) }
            // Effort samples are related to the workout; match by time instead of relationship queries.
            let window = w.start.addingTimeInterval(-60)...w.end.addingTimeInterval(15 * 60)
            if let own = effort.first(where: { window.contains($0.date) }) {
                w.effort = own.value
            } else if let est = estimatedEffort.first(where: { window.contains($0.date) }) {
                w.effort = est.value
                w.effortIsEstimate = true
            }
            w.hrRecovery = hrRecovery.first { abs($0.date.timeIntervalSince(w.end)) <= 10 * 60 }?.value
            return w
        }
    }

    /// Day strain 0 to 21: 21·(1 − e^(−TRIMP/τ)), the saturating form GenieMax uses
    /// (github.com/satayutata/geniemax-core, docs/HOW-IT-WORKS.md section 3).
    public static func strain(trimp: Double, tau: Double) -> Double {
        21 * (1 - exp(-trimp / tau))
    }

    /// GenieMax solves τ from a WHOOP reading, which we don't have. Calibration choice instead: your median
    /// training-day TRIMP over the last 60 days lands at mid-scale, 10.5. Solving 10.5 = 21·(1 − e^(−m/τ))
    /// gives τ = m / ln 2. So harder than your usual day reads above 10.5, easier below. Needs 5 training days.
    public static func calibrateTau(_ days: [TrainingDay], endingOn day: Date) -> Double? {
        let since = Calendar.current.date(byAdding: .day, value: -60, to: day)!
        let trained = days.filter { $0.date > since && $0.date <= day && $0.trimp > 0 }.map(\.trimp)
        guard trained.count >= 5, let m = Stats.percentile(trained, 0.5), m > 0 else { return nil }
        return m / log(2)
    }

    /// Fitness and fatigue as exponentially weighted daily load, k = e^(−1/42) and e^(−1/7): Banister's
    /// impulse-response model in the form TrainingPeaks and GenieMax use. Form = fitness − fatigue.
    public static func fitnessFatigue(_ loads: [Double]) -> (fitness: Double, fatigue: Double)? {
        guard !loads.isEmpty else { return nil }
        let kc = exp(-1.0 / 42), ka = exp(-1.0 / 7)
        var ctl = 0.0, atl = 0.0
        for l in loads {
            ctl = ctl * kc + l * (1 - kc)
            atl = atl * ka + l * (1 - ka)
        }
        return (ctl, atl)
    }

    /// Session RPE load: effort rating × minutes. Foster et al. (2001), "A new approach to monitoring exercise
    /// training", J Strength Cond Res 15(1). Counts lifting fairly, where heart rate undercounts it.
    public static func srpe(_ w: WorkoutSummary) -> Double {
        (w.effort ?? 0) * w.duration / 60
    }

    public static func evaluate(_ s: HealthSnapshot, day: Date, recovery: Double?) -> TrainingResult {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: s.workouts) { cal.startOfDay(for: $0.start) }
        let first = s.workouts.map { cal.startOfDay(for: $0.start) }.min() ?? day
        let count = (cal.dateComponents([.day], from: first, to: day).day ?? 0) + 1
        var days: [TrainingDay] = (0..<count).map { i in
            let d = cal.date(byAdding: .day, value: i, to: first)!
            let w = byDay[d] ?? []
            return TrainingDay(date: d, trimp: w.compactMap { $0.heartRate?.trimp }.reduce(0, +),
                               strain: nil, srpe: w.map(srpe).reduce(0, +))
        }
        let tau = calibrateTau(days, endingOn: day)
        if let tau {
            days = days.map { TrainingDay(date: $0.date, trimp: $0.trimp, strain: strain(trimp: $0.trimp, tau: tau), srpe: $0.srpe) }
        }
        let hasHR = s.workouts.contains { $0.heartRate != nil }
        let load = hasHR ? fitnessFatigue(days.map(\.trimp)) : nil
        let observedMax = s.workouts.compactMap { $0.heartRate?.max }.max()
        // Strain target from recovery, WHOOP strain coach style. Our scale puts your usual training day at 10.5,
        // so recovery 50 points there, 0 points 5 lower and 100 points 5 higher, with a band of ±2.
        // A design choice and a suggestion, not a rule.
        let target = recovery.map { r -> ClosedRange<Double> in
            let centre = 10.5 + 5 * (r - 50) / 50
            return max(0, centre - 2)...min(21, centre + 2)
        }
        return TrainingResult(
            profile: profile(s, day: day, observedMax: observedMax),
            tau: tau,
            today: days.last { cal.isDate($0.date, inSameDayAs: day) },
            fitness: load?.fitness,
            fatigue: load?.fatigue,
            days: days,
            strainTarget: tau == nil ? nil : target
        )
    }
}

public struct ActivityLine: Identifiable, Sendable {
    public let name: String
    public let count: Int
    public let minutes: Double
    public let usualCount: Double      // per week, previous 4 weeks
    public let usualMinutes: Double
    public var id: String { name }
}

public enum ActivityEngine {
    /// This week (last 7 days) per activity type against the weekly average of the 4 weeks before.
    public static func weekly(_ workouts: [WorkoutSummary], endingOn day: Date) -> [ActivityLine] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: day)!
        let weekStart = cal.date(byAdding: .day, value: -7, to: end)!
        let baseStart = cal.date(byAdding: .day, value: -28, to: weekStart)!
        let thisWeek = workouts.filter { $0.start >= weekStart && $0.start < end }
        let before = workouts.filter { $0.start >= baseStart && $0.start < weekStart }
        let names = Set((thisWeek + before).map(\.name))
        return names.map { n in
            let a = thisWeek.filter { $0.name == n }, b = before.filter { $0.name == n }
            return ActivityLine(name: n, count: a.count, minutes: a.reduce(0) { $0 + $1.duration / 60 },
                                usualCount: Double(b.count) / 4, usualMinutes: b.reduce(0) { $0 + $1.duration / 60 } / 4)
        }
        .sorted { ($0.minutes, $0.usualMinutes) > ($1.minutes, $1.usualMinutes) }
    }
}
