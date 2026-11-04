import Foundation

/// Planning around a fixed wake-up time: when to be in bed to get your sleep need, and how regularly you wake.
/// Apple Health doesn't share the Sleep Schedule from the Health app with other apps, so the wake goal is a setting.
public enum SleepPlan {
    /// Minutes after midnight for a clock time.
    public static func clock(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Wraps minutes into 0..<1440, so 23:00 minus an hour works across midnight.
    public static func wrap(_ m: Double) -> Double {
        let r = m.truncatingRemainder(dividingBy: 1440)
        return r < 0 ? r + 1440 : r
    }

    /// Your typical share of time in bed spent asleep: the median over the last 30 nights.
    public static func efficiency(_ nights: [SleepNight]) -> Double? {
        let e = nights.suffix(30).compactMap { n -> Double? in
            let inBed = n.end.timeIntervalSince(n.start)
            return inBed > 0 ? n.asleep / inBed : nil
        }
        return e.count >= 5 ? Stats.percentile(e, 0.5) : nil
    }

    /// Time to be in bed: wake goal minus your sleep need stretched by your efficiency, since nobody sleeps every
    /// minute in bed (time in bed = need ÷ efficiency). A design rule built from your own nights; the 7-hour floor
    /// and the need itself come from Settings and the sleep consensus (Watson et al. 2015).
    public static func bedtime(wake: Double, needHours: Double, efficiency: Double) -> Double {
        wrap(wake - needHours * 60 / max(0.5, min(1, efficiency)))
    }

    /// How far a night's wake-up landed from the goal, in minutes: positive is later. Wrapped to ±12 hours.
    public static func wakeDeviation(_ n: SleepNight, goal: Double) -> Double {
        var d = clock(n.end) - goal
        if d > 720 { d -= 1440 }
        if d < -720 { d += 1440 }
        return d
    }

    /// Your usual wake time, the median over the last 30 nights, as a starting point for the goal.
    public static func usualWake(_ nights: [SleepNight]) -> Double? {
        let w = nights.suffix(30).map { clock($0.end) }
        return w.count >= 5 ? Stats.percentile(w, 0.5) : nil
    }

    /// Within 30 minutes of the goal counts as on time. Regular sleep timing has been linked to health outcomes
    /// independently of duration, and sleep regularity predicted mortality more strongly than duration in a UK
    /// Biobank cohort (Windred et al. 2024, "Sleep regularity is a stronger predictor of mortality risk than sleep
    /// duration", Sleep 47(1)). The 30-minute window is a design choice.
    public static let onTimeMinutes = 30.0

    /// Score for a wake-up: 100 within 30 minutes, falling to 0 at 2 hours off.
    public static func wakeScore(deviation: Double) -> Double {
        let off = abs(deviation)
        return off <= onTimeMinutes ? 100 : max(0, 100 * (1 - (off - onTimeMinutes) / 90))
    }
}
