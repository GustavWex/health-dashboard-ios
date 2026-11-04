import Foundation

/// 30 seconds of wrist data from the watch: how much the wrist moved, and heart rate when there is a reading.
/// `activity` is the mean absolute deviation of the acceleration magnitude from its own mean over the epoch, in g:
/// near 0.003 at rest on a table, above 0.02 for a turn in bed, far higher when awake and moving.
/// Scoring sleep and wake from movement in fixed epochs is actigraphy (Cole, Kripke, Gruen, Mullaney and Gillin
/// 1992, "Automatic sleep/wake identification from wrist activity", Sleep 15(5)), the basis of wrist sleep tracking.
public struct MotionEpoch: Codable, Sendable, Equatable {
    public let time: Date
    public let activity: Double
    public let heartRate: Double?

    public init(time: Date, activity: Double, heartRate: Double? = nil) {
        self.time = time
        self.activity = activity
        self.heartRate = heartRate
    }
}

public enum WakeReason: String, Codable, Sendable {
    case movement          // restless enough to suggest light sleep or waking
    case heartRate         // heart rate rising above the window's level
    case deadline          // nothing earlier; woken at the latest time
}

/// Smart alarm: during the window before your wake time, wake at the first sign of light sleep, otherwise at the
/// deadline. Light sleep and brief arousals come with body movement and a rising heart rate, while deep sleep is
/// still, which is what movement-based smart alarms look for. Being woken from deep sleep gives worse sleep inertia
/// (Tassi and Muzet 2000, "Sleep inertia", Sleep Med Rev 4(4)). Thresholds are design choices, tuned from logs.
public enum SmartWake {
    /// Movement above this, or 3 times the window's own median, marks an active epoch.
    public static let movementFloor = 0.02
    /// Heart rate 10% above the window median for two epochs.
    public static let heartRateRise = 1.10

    public static func decide(_ epochs: [MotionEpoch], windowStart: Date, wakeBy: Date, now: Date) -> WakeReason? {
        if now >= wakeBy { return .deadline }
        let inWindow = epochs.filter { $0.time >= windowStart }
        // Two minutes in before judging, so the baseline means something
        guard inWindow.count >= 4, let median = Stats.percentile(inWindow.map(\.activity), 0.5) else { return nil }
        let threshold = max(movementFloor, 3 * median)
        let recent = inWindow.suffix(3)
        if recent.filter({ $0.activity > threshold }).count >= 2 { return .movement }
        let hr = inWindow.compactMap(\.heartRate)
        if hr.count >= 4, let hrMedian = Stats.percentile(hr, 0.5) {
            let last = inWindow.suffix(2).compactMap(\.heartRate)
            if last.count == 2 && last.allSatisfy({ $0 >= hrMedian * heartRateRise }) { return .heartRate }
        }
        return nil
    }
}

public enum NapState: Equatable, Sendable {
    case fallingAsleep                 // not asleep yet
    case asleep(since: Date)
    case wake(WakeReason)
}

/// Smart nap: the nap length counts from when you actually fall asleep, not from when you lie down, and the nap
/// is capped so it ends before deep sleep sets in. Short naps of about 10 to 20 minutes improved alertness with
/// little grogginess, while a 30-minute nap brought sleep inertia (Brooks and Lack 2006, "A brief afternoon nap
/// following nocturnal sleep restriction: which nap duration is most recuperative?", Sleep 29(6)). Apple's smart
/// alarm sessions also last at most 30 minutes, which matches the cap.
public enum NapPlan {
    /// Still below this for 5 minutes counts as asleep.
    public static let stillness = 0.012
    public static let onsetEpochs = 10
    public static let cap: TimeInterval = 30 * 60

    public static func decide(_ epochs: [MotionEpoch], start: Date, napMinutes: Double, now: Date) -> NapState {
        if now >= start.addingTimeInterval(cap) { return .wake(.deadline) }
        var run = 0
        for (i, e) in epochs.enumerated() where e.time >= start {
            run = e.activity < stillness ? run + 1 : 0
            if run >= onsetEpochs {
                let onset = epochs[i - onsetEpochs + 1].time
                return now >= onset.addingTimeInterval(napMinutes * 60) ? .wake(.deadline) : .asleep(since: onset)
            }
        }
        return .fallingAsleep
    }
}

/// Desk drowsiness: a still wrist with heart rate falling below where it was when you sat down. Heart rate drops at
/// the transition into sleep (Trinder et al. 2001, "Autonomic activity during human sleep as a function of time and
/// sleep stage", J Sleep Res 10(4)). Reading can also be still, so without heart rate it waits longer. A nudge, not
/// a diagnosis; thresholds are design choices.
public enum DozeDetector {
    public static let stillness = 0.012
    /// 8% below the first 10 minutes' median heart rate.
    public static let heartRateDrop = 0.92

    public static func baseline(_ epochs: [MotionEpoch]) -> Double? {
        guard let first = epochs.first?.time else { return nil }
        let hr = epochs.filter { $0.time < first.addingTimeInterval(600) }.compactMap(\.heartRate)
        return hr.count >= 5 ? Stats.percentile(hr, 0.5) : nil
    }

    public static func isDozing(_ epochs: [MotionEpoch], baselineHR: Double?) -> Bool {
        let hasHR = baselineHR != nil
        let needed = hasHR ? 6 : 10           // 3 minutes still with a heart rate drop, or 5 minutes still without one
        let recent = epochs.suffix(needed)
        guard recent.count == needed, recent.allSatisfy({ $0.activity < stillness }) else { return false }
        guard let base = baselineHR else { return true }
        let hr = recent.suffix(4).compactMap(\.heartRate)
        guard hr.count >= 2, let mean = Stats.mean(hr) else { return false }
        return mean <= base * heartRateDrop
    }
}
