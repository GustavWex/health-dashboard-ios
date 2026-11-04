import Foundation

public enum ScoreStatus: Sendable {
    case good, fair, poor

    /// 80 and up is good, 60 to 80 fair, below 60 poor. A design choice.
    public init(_ score: Double) {
        self = score >= 80 ? .good : (score >= 60 ? .fair : .poor)
    }
}

public enum SleepComponentKind: String, CaseIterable, Sendable {
    case duration, interruptions, regularity, hrv, heartRate, depth

    /// Weights are a design choice: duration and continuity first, physiology next, stage depth last
    /// because watch stage estimates are rough. Missing components have their weight redistributed.
    public var weight: Double {
        switch self {
        case .duration: 0.30
        case .interruptions: 0.20
        case .regularity: 0.15
        case .hrv: 0.15
        case .heartRate: 0.10
        case .depth: 0.10
        }
    }
}

public struct SleepComponent: Identifiable, Sendable {
    public let kind: SleepComponentKind
    public let score: Double          // 0 to 100
    public let value: Double          // the raw measure, in the unit the UI shows
    public var status: ScoreStatus { ScoreStatus(score) }
    public var id: SleepComponentKind { kind }
}

public struct SleepScore: Sendable {
    public let date: Date
    public let score: Double
    public let components: [SleepComponent]
    public var status: ScoreStatus { ScoreStatus(score) }

    public func component(_ kind: SleepComponentKind) -> SleepComponent? {
        components.first { $0.kind == kind }
    }

    /// Points each part cost against a perfect 100: weight·(100 − part score)/Σ weights present. The total is a
    /// weighted mean, so these add up exactly to 100 − score. Largest loss first.
    public var pointsLost: [(kind: SleepComponentKind, points: Double)] {
        let wsum = components.reduce(0) { $0 + $1.kind.weight }
        guard wsum > 0 else { return [] }
        return components.map { ($0.kind, $0.kind.weight * (100 - $0.score) / wsum) }.sorted { $0.points > $1.points }
    }
}

/// Our own sleep score with the same six parts as the Withings one. Withings' formula is not public, so every
/// mapping below is ours and documented. Each part scores 0 to 100, the total is their weighted mean.
public enum SleepScoreEngine {
    public static func score(_ s: HealthSnapshot, night: SleepNight, needHours: Double) -> SleepScore {
        var parts: [SleepComponent] = []
        let day = night.date

        // Duration against your sleep need: 50% of need scores 0, full need scores 100.
        let hours = night.asleep / 3600
        parts.append(SleepComponent(kind: .duration, score: 100 * clamp((hours / needHours - 0.5) / 0.5), value: hours))

        // Wake after sleep onset. 30 min is the usual research cutoff for clinically meaningful wake:
        // Lichstein et al. (2003), "Quantitative criteria for insomnia", Behav Res Ther 41(4).
        // Up to 30 min scores 100, falling linearly to 0 at 120 min.
        let wasoMin = night.waso / 60
        parts.append(SleepComponent(kind: .interruptions, score: 100 * clamp(1 - (wasoMin - 30) / 90), value: wasoMin))

        // Regularity: Sleep Regularity Index over the 7 days ending this morning; negative SRI scores 0.
        if let sri = regularityIndex(nights: s.sleep, naps: s.naps, endingOn: day) {
            parts.append(SleepComponent(kind: .regularity, score: clamp(sri / 100) * 100, value: sri))
        }

        // Physiology against your own 60-day baseline. At or better than baseline scores 100, 3 SD worse scores 0.
        if let z = RecoveryEngine.z(s.hrv, on: day, logScale: true), let v = s.hrv.value(on: day) {
            parts.append(SleepComponent(kind: .hrv, score: 100 * clamp(1 + min(z, 0) / 3), value: v))
        }
        if let z = RecoveryEngine.z(s.sleepingHR, on: day, logScale: false), let v = s.sleepingHR.value(on: day) {
            parts.append(SleepComponent(kind: .heartRate, score: 100 * clamp(1 - max(z, 0) / 3), value: v))
        }

        // Depth: deep plus REM share of sleep, against your own baseline. Only nights with stage data count.
        let depth = s.sleep.filter { $0.deep + $0.rem > 0 && $0.asleep > 0 }
            .map { DailyValue(date: $0.date, value: ($0.deep + $0.rem) / $0.asleep) }
        if let z = RecoveryEngine.z(depth, on: day, logScale: false), let v = depth.value(on: day) {
            parts.append(SleepComponent(kind: .depth, score: 100 * clamp(1 + min(z, 0) / 3), value: v * 100))
        }

        let wsum = parts.reduce(0) { $0 + $1.kind.weight }
        let total = parts.reduce(0) { $0 + $1.kind.weight * $1.score } / wsum
        return SleepScore(date: day, score: total, components: parts)
    }

    /// Sleep Regularity Index: the chance of being in the same state (asleep or awake) at two moments 24 h apart,
    /// scaled to -100...100. Phillips et al. (2017), "Irregular sleep/wake patterns are associated with poorer
    /// academic performance and delayed circadian and sleep/wake timing", Scientific Reports 7.
    /// Computed on 1-minute epochs over the 7 days ending at noon on `day`. Needs at least 4 nights in the window.
    public static func regularityIndex(nights: [SleepNight], naps: [Nap], endingOn day: Date) -> Double? {
        let cal = Calendar.current
        let days = 7
        guard let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day),
              let start = cal.date(byAdding: .day, value: -days, to: end) else { return nil }
        let window = DateInterval(start: start, end: end)
        let inWindow = nights.filter { $0.end > start && $0.start < end }
        guard inWindow.count >= 4 else { return nil }

        let minutes = Int(window.duration / 60)
        var asleep = [Bool](repeating: false, count: minutes)
        let intervals = inWindow.flatMap(\.asleepIntervals) + naps.map { DateInterval(start: $0.start, end: $0.end) }
        for i in intervals {
            let a = max(0, Int(i.start.timeIntervalSince(start) / 60))
            let b = min(minutes, Int(i.end.timeIntervalSince(start) / 60))
            if a < b { for m in a..<b { asleep[m] = true } }
        }
        let shift = minutes / days
        var same = 0
        for m in 0..<(minutes - shift) where asleep[m] == asleep[m + shift] { same += 1 }
        return -100 + 200 * Double(same) / Double(minutes - shift)
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
