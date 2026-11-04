import Foundation

public enum Zone: Int, Comparable, Sendable {
    case recover = 0, moderate, push
    public static func < (a: Zone, b: Zone) -> Bool { a.rawValue < b.rawValue }
}

public struct RecoveryResult: Sendable {
    public let score: Double?
    public let zone: Zone?
    public let hrv: Double?
    public let hrvZ: Double?
    public let rhr: Double?
    public let rhrZ: Double?
    public let rr: Double?
    public let rrZ: Double?
    public let hrvTrendZ: Double?    // 7-day rolling lnHRV vs its own 60-day history
    public let sleepHours: Double?
    public let low: Double          // personal "recover" threshold
    public let high: Double         // personal "push" threshold
    public let personalZones: Bool
    public let reasons: [String]
    /// Each input's share of today's score, largest effect first.
    public var drivers: [RecoveryDriver] = []
}

/// One input to the recovery score. The score is 100·Φ(Σ contribution), so contributions add up exactly:
/// the explanation is the model itself, not an approximation of it.
public struct RecoveryDriver: Identifiable, Sendable {
    public enum Input: String, Sendable { case hrv, restingHR, breathing, sleep }
    public let input: Input
    public let value: Double
    /// Your typical value over the 60-day baseline (geometric mean for HRV, which is scored on a log scale).
    public let typical: Double
    /// Standard deviations from your baseline, signed so that positive is better for recovery.
    public let goodZ: Double
    /// weight · goodZ / Σ weights of the inputs present, in z units.
    public let contribution: Double
    public var id: String { input.rawValue }
}

public enum RecoveryEngine {
    public static let baselineDays = 60
    public static let minBaseline = 14

    /// z-score of today's value vs the previous 60 days.
    /// HRV is log transformed first since it is right skewed: Plews et al. (2012),
    /// "Heart rate variability in elite triathletes", Eur J Appl Physiol 112:3729-3741.
    public static func z(_ series: [DailyValue], on day: Date, logScale: Bool) -> Double? {
        let f: (Double) -> Double = logScale ? { log($0) } : { $0 }
        guard let today = series.value(on: day), !logScale || today > 0 else { return nil }
        let base = series.baseline(before: day, days: baselineDays)
            .filter { !logScale || $0 > 0 }
            .map(f)
        guard base.count >= minBaseline, let m = Stats.mean(base), let sd = Stats.sd(base), sd > 0 else { return nil }
        return (f(today) - m) / sd
    }

    /// Mean of the 60-day baseline, back on the original scale.
    static func typical(_ series: [DailyValue], on day: Date, logScale: Bool) -> Double? {
        let base = series.baseline(before: day, days: baselineDays).filter { !logScale || $0 > 0 }
        guard base.count >= minBaseline else { return nil }
        return logScale ? Stats.mean(base.map { log($0) }).map { exp($0) } : Stats.mean(base)
    }

    /// The score's inputs with their exact contributions (see `rawScore`).
    public static func drivers(on day: Date, _ s: HealthSnapshot) -> [RecoveryDriver] {
        let sleepSeries = s.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) }
        let inputs: [(RecoveryDriver.Input, [DailyValue], Bool, Double, Double)] = [
            (.hrv, s.hrv, true, 0.55, 1), (.restingHR, s.restingHR, false, 0.20, -1),
            (.breathing, s.respiratoryRate, false, 0.10, -1), (.sleep, sleepSeries, false, 0.15, 1),
        ]
        let present = inputs.compactMap { input, series, log, w, sign -> (RecoveryDriver.Input, Double, Double, Double, Double)? in
            guard let z = z(series, on: day, logScale: log), let v = series.value(on: day),
                  let t = typical(series, on: day, logScale: log) else { return nil }
            return (input, v, t, w, sign * z)
        }
        let wsum = present.reduce(0) { $0 + $1.3 }
        guard wsum > 0 else { return [] }
        return present.map { RecoveryDriver(input: $0.0, value: $0.1, typical: $0.2, goodZ: $0.4, contribution: $0.3 * $0.4 / wsum) }
            .sorted { abs($0.contribution) > abs($1.contribution) }
    }

    /// Score from driver contributions: 100·Φ(Σ c), the same function as `rawScore`.
    public static func score(contributions c: [Double]) -> Double {
        100 * Stats.normalCDF(c.reduce(0, +))
    }

    /// Exact Shapley values in score points: how much each input moves the score away from 50, the score of a
    /// morning where every input sits at your normal. "Absent" means at your normal (contribution 0). With at
    /// most four inputs all orderings are enumerated, so the values are exact and add up to score − 50.
    /// Shapley (1953), "A value for n-person games", Contributions to the Theory of Games II; applied to model
    /// explanations as SHAP by Lundberg and Lee (2017), "A unified approach to interpreting model predictions", NeurIPS.
    public static func breakdown(_ drivers: [RecoveryDriver]) -> [(input: RecoveryDriver.Input, points: Double)] {
        let n = drivers.count
        guard n > 0 else { return [] }
        func value(_ members: Set<Int>) -> Double { score(contributions: members.map { drivers[$0].contribution }) }
        func permutations(_ a: [Int]) -> [[Int]] {
            a.count <= 1 ? [a] : a.indices.flatMap { i in permutations(Array(a[..<i] + a[(i + 1)...])).map { [a[i]] + $0 } }
        }
        let orders = permutations(Array(0..<n))
        var phi = [Double](repeating: 0, count: n)
        for order in orders {
            var members = Set<Int>()
            for i in order {
                let before = value(members)
                members.insert(i)
                phi[i] += value(members) - before
            }
        }
        return drivers.indices.map { (drivers[$0].input, phi[$0] / Double(orders.count)) }
    }

    /// Counterfactual: today's score if this one input had been at your normal and the others unchanged.
    public static func whatIf(_ drivers: [RecoveryDriver], normal input: RecoveryDriver.Input) -> Double {
        score(contributions: drivers.filter { $0.input != input }.map(\.contribution))
    }

    /// Score before safety gates: 100·Φ(0.55·zHRV − 0.20·zRHR − 0.10·zRR + 0.15·zSleep), with the weights
    /// of missing inputs redistributed. Weights from GenieMax core (github.com/satayutata/geniemax-core,
    /// docs/HOW-IT-WORKS.md, section 5).
    public static func rawScore(on day: Date, _ s: HealthSnapshot)
        -> (score: Double, hrvZ: Double?, rhrZ: Double?, rrZ: Double?)? {
        let hrvZ = z(s.hrv, on: day, logScale: true)
        let rhrZ = z(s.restingHR, on: day, logScale: false)
        guard hrvZ != nil || rhrZ != nil else { return nil }
        let rrZ = z(s.respiratoryRate, on: day, logScale: false)
        let sleepSeries = s.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) }
        let sleepZ = z(sleepSeries, on: day, logScale: false)

        var parts: [(w: Double, v: Double)] = []
        if let hrvZ { parts.append((0.55, hrvZ)) }
        if let rhrZ { parts.append((0.20, -rhrZ)) }   // higher resting HR is worse
        if let rrZ { parts.append((0.10, -rrZ)) }     // higher breathing rate is worse
        if let sleepZ { parts.append((0.15, sleepZ)) }
        let wsum = parts.reduce(0) { $0 + $1.w }
        let combined = parts.reduce(0) { $0 + $1.w * $1.v } / wsum
        return (100 * Stats.normalCDF(combined), hrvZ, rhrZ, rrZ)
    }

    /// Mean lnHRV over the 7 days ending on `day`, needing at least 3 readings.
    /// Weekly averaging tracks adaptation better than single days, with benefit leveling off after 3 to 4
    /// valid days: Plews et al. (2014), "Monitoring training with heart-rate variability: how much
    /// compliance is needed for valid assessment?", Int J Sports Physiol Perform, PMID 24334285.
    public static func rollingLnHRV(_ hrv: [DailyValue], on day: Date) -> Double? {
        let week = hrv.recent(days: 7, from: day).map(\.value).filter { $0 > 0 }.map { log($0) }
        return week.count >= 3 ? Stats.mean(week) : nil
    }

    /// z-score of today's 7-day rolling lnHRV against the rolling values of the previous 60 days.
    /// Compares like with like: a weekly average against weekly averages, not against single days.
    public static func hrvTrendZ(_ hrv: [DailyValue], on day: Date) -> Double? {
        let cal = Calendar.current
        guard let today = rollingLnHRV(hrv, on: day) else { return nil }
        let past = (1...baselineDays).compactMap { back in
            rollingLnHRV(hrv, on: cal.date(byAdding: .day, value: -back, to: day)!)
        }
        guard past.count >= minBaseline, let m = Stats.mean(past), let sd = Stats.sd(past), sd > 0 else { return nil }
        return (today - m) / sd
    }

    public static func history(_ s: HealthSnapshot, days: Int, endingOn day: Date) -> [DailyValue] {
        let cal = Calendar.current
        return (0..<days).reversed().compactMap { back in
            let d = cal.date(byAdding: .day, value: -back, to: day)!
            return rawScore(on: d, s).map { DailyValue(date: d, value: $0.score) }
        }
    }

    public static func evaluate(_ s: HealthSnapshot, day: Date) -> RecoveryResult {
        let cal = Calendar.current

        // Personal zones: your own 25th and 75th percentile over the last 30 days, instead of fixed cutoffs.
        // Design from Omnio (getomn.io blog, adaptive training).
        let past = history(s, days: 31, endingOn: day).filter { $0.date < day }.map(\.value)
        let personal = past.count >= 14
        let low = personal ? (Stats.percentile(past, 0.25) ?? 33) : 33
        let high = personal ? (Stats.percentile(past, 0.75) ?? 66) : 66

        let hrvToday = s.hrv.value(on: day)
        let rhrToday = s.restingHR.value(on: day)
        let rrToday = s.respiratoryRate.value(on: day)
        let night = s.sleep.first { cal.isDate($0.date, inSameDayAs: day) }
        let sleepHours = night.map { $0.asleep / 3600 }

        guard let raw = rawScore(on: day, s) else {
            return RecoveryResult(
                score: nil, zone: nil, hrv: hrvToday, hrvZ: nil, rhr: rhrToday, rhrZ: nil,
                rr: rrToday, rrZ: nil, hrvTrendZ: nil, sleepHours: sleepHours, low: low, high: high, personalZones: false,
                reasons: ["Needs 14 nights of HRV or resting heart rate, plus a reading from last night. Wear your watch to bed."]
            )
        }

        var zone: Zone = raw.score < low ? .recover : (raw.score >= high ? .push : .moderate)
        var reasons: [String] = []

        if raw.score < 20 {
            zone = .recover
            reasons.append("Score is under the absolute floor of 20.")
        }

        // Safety gates (Omnio): one badly off signal can't be hidden by the others.
        // Thresholds of 1 and 2 SD are a design choice, not a published cutoff.
        if let z = raw.hrvZ {
            if z < -2 {
                zone = min(zone, .recover)
                reasons.append(String(format: "HRV is %.1f SD below your baseline.", -z))
            } else if z < -1 {
                zone = min(zone, .moderate)
                reasons.append(String(format: "HRV is %.1f SD below your baseline.", -z))
            } else if z > 1 {
                reasons.append("HRV is well above your baseline.")
            }
        }
        // Trend gate: a week of suppressed HRV caps the day even when this morning looks fine.
        // The -1 cutoff is a design choice; the papers above use a personal smallest worthwhile change.
        let trendZ = hrvTrendZ(s.hrv, on: day)
        if let z = trendZ, z < -1 {
            zone = min(zone, .moderate)
            reasons.append("Your 7-day HRV average has dropped below your normal range.")
        }
        if let z = raw.rhrZ {
            if z > 2 {
                zone = min(zone, .recover)
                reasons.append(String(format: "Resting HR is %.1f SD above your baseline.", z))
            } else if z > 1 {
                zone = min(zone, .moderate)
                reasons.append(String(format: "Resting HR is %.1f SD above your baseline.", z))
            }
        }
        if let z = raw.rrZ, z > 2 {
            reasons.append(String(format: "Breathing rate is %.1f SD above your baseline.", z))
        }
        if let hours = sleepHours {
            let pastSleep = s.sleep.filter { $0.date < day }.suffix(60).map { $0.asleep / 3600 }
            if pastSleep.count >= 14, let p10 = Stats.percentile(pastSleep, 0.10), let p25 = Stats.percentile(pastSleep, 0.25) {
                if hours < p10 {
                    zone = min(zone, .moderate)
                    reasons.append("Last night was in your shortest 10% of nights.")
                } else if hours < p25 {
                    reasons.append("Last night was shorter than usual.")
                }
            }
        }
        if let t = s.wristTemp.value(on: day) {
            let base = s.wristTemp.baseline(before: day, days: 30)
            if base.count >= 7, let m = Stats.mean(base), t - m > 0.5 {
                zone = min(zone, .moderate)
                reasons.append(String(format: "Wrist temperature is %.1f °C above your baseline. Can be an early sign of illness.", t - m))
            }
        }

        if reasons.isEmpty { reasons.append("All signals are within your normal range.") }
        if !personal { reasons.append("Zones use generic cutoffs until you have 14 days of scores.") }

        var result = RecoveryResult(
            score: raw.score, zone: zone, hrv: hrvToday, hrvZ: raw.hrvZ, rhr: rhrToday, rhrZ: raw.rhrZ,
            rr: rrToday, rrZ: raw.rrZ, hrvTrendZ: trendZ, sleepHours: sleepHours, low: low, high: high, personalZones: personal, reasons: reasons
        )
        result.drivers = drivers(on: day, s)
        return result
    }
}
