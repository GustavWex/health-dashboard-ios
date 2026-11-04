import Foundation

public struct BodyResult: Sendable {
    public let latestWeight: Double?
    public let trendWeight: Double?
    public let ratePerWeek: Double?
    public let bodyFat: Double?          // percent
    public let leanMass: Double?
    public let leanRatePerMonth: Double?
    public let trend: [DailyValue]
    /// From the Withings API, when connected.
    public var muscleMass: Double? = nil
    public var muscleRatePerMonth: Double? = nil
    public var waterPercent: Double? = nil
    public var visceralFat: Double? = nil
    public var boneMass: Double? = nil
}

public enum BodyEngine {
    /// Exponential moving average, v_t = v_(t-1) + α(x_t − v_(t-1)), seeded with the first value.
    /// Smooths out water and food swings between weigh-ins, as in Walker, "The Hacker's Diet" (1991),
    /// which uses α = 0.1. α = 0.2 here reacts faster; a design choice.
    public static func ema(_ pts: [DailyValue], alpha: Double = 0.2) -> [DailyValue] {
        var out: [DailyValue] = []
        var prev: Double?
        for p in pts {
            let v = prev.map { $0 + alpha * (p.value - $0) } ?? p.value
            out.append(DailyValue(date: p.date, value: v))
            prev = v
        }
        return out
    }

    /// Rate is the OLS slope of the trend weight over 28 days, lean mass rate over 56 days.
    public static func evaluate(_ s: HealthSnapshot, day: Date) -> BodyResult {
        let trend = ema(s.weight)
        var r = BodyResult(
            latestWeight: s.weight.last?.value,
            trendWeight: trend.last?.value,
            ratePerWeek: Stats.slopePerDay(trend.recent(days: 28, from: day)).map { $0 * 7 },
            bodyFat: s.bodyFat.last.map { $0.value * 100 },
            leanMass: s.leanMass.last?.value,
            leanRatePerMonth: Stats.slopePerDay(s.leanMass.recent(days: 56, from: day)).map { $0 * 30 },
            trend: trend
        )
        // Muscle mass rate: same 56-day OLS slope as lean mass. Water as a share of that day's weigh-in.
        r.muscleMass = s.muscleMass.last?.value
        r.muscleRatePerMonth = Stats.slopePerDay(s.muscleMass.recent(days: 56, from: day)).map { $0 * 30 }
        if let w = s.bodyWater.last, let kg = s.weight.value(on: w.date) { r.waterPercent = 100 * w.value / kg }
        r.visceralFat = s.visceralFat.last?.value
        r.boneMass = s.boneMass.last?.value
        return r
    }
}
