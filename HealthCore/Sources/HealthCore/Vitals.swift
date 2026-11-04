import Foundation

public enum VitalStatus: Sendable {
    case normal, low, high, learning, noReading
}

public struct VitalCheck: Identifiable, Sendable {
    public let name: String
    public let unit: String
    public let value: Double?
    public let low: Double?
    public let high: Double?
    public let status: VitalStatus
    /// The last 7 nights, for drawing recent readings against the range.
    public var recent: [DailyValue] = []
    public var id: String { name }
}

public struct VitalsResult: Sendable {
    public let checks: [VitalCheck]
    /// Several readings outside their range on the same night: worth a look, in the spirit of Apple's Vitals app.
    public var severalUnusual: Bool { checks.filter { $0.status == .low || $0.status == .high }.count >= 2 }
}

public enum VitalsEngine {
    public static let baselineDays = 60
    public static let minBaseline = 14
    /// Width of the personal normal range in SDs. A design choice: wide enough that a normal night rarely
    /// trips it, since an alert that fires often trains you to check constantly, which helps nobody.
    public static let width = 2.0

    /// Overnight readings against your own range over the previous 60 days. Wellness, not diagnosis:
    /// the UI says "unusual for you", never what it might mean medically.
    public static func check(_ s: HealthSnapshot, day: Date) -> VitalsResult {
        let sleepHours = s.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) }
        let spo2 = s.oxygenSaturation.map { DailyValue(date: $0.date, value: $0.value * 100) }
        return VitalsResult(checks: [
            check("HRV", "ms", s.hrv, day),
            check("Resting HR", "bpm", s.restingHR, day),
            check("Breathing rate", "/min", s.respiratoryRate, day),
            check("Wrist temperature", "°C", s.wristTemp, day),
            check("Blood oxygen", "%", spo2, day),
            check("Sleep", "h", sleepHours, day),
        ].compactMap { $0 })
    }

    /// nil when the metric has never been recorded, so it doesn't clutter the list.
    static func check(_ name: String, _ unit: String, _ series: [DailyValue], _ day: Date) -> VitalCheck? {
        guard !series.isEmpty else { return nil }
        let value = series.value(on: day)
        let base = series.baseline(before: day, days: baselineDays)
        let recent = series.recent(days: 7, from: day)
        guard base.count >= minBaseline, let m = Stats.mean(base), let sd = Stats.sd(base) else {
            var c = VitalCheck(name: name, unit: unit, value: value, low: nil, high: nil, status: .learning)
            c.recent = recent
            return c
        }
        let low = m - width * sd, high = m + width * sd
        let status: VitalStatus
        if let v = value {
            status = v < low ? .low : (v > high ? .high : .normal)
        } else {
            status = .noReading
        }
        var c = VitalCheck(name: name, unit: unit, value: value, low: low, high: high, status: status)
        c.recent = recent
        return c
    }
}
