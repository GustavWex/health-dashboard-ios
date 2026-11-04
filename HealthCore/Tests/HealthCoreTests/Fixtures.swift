import Foundation
@testable import HealthCore

/// Synthetic fixtures shared by the tests. They must match Tests/reference/golden.py,
/// which produces the expected values independently.
enum Fixture {
    static let cal = Calendar.current

    /// "Today" for every fixture. Mid summer, so the 120-day window doesn't cross a DST change in Europe.
    static let today = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!)

    static func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    static func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
    }

    static func series(_ days: ClosedRange<Int>, _ f: (Int) -> Double) -> [DailyValue] {
        days.map { DailyValue(date: day($0), value: f($0)) }
    }

    static func night(_ offset: Int, hours: Double) -> SleepNight {
        let end = at(offset, 7)
        return SleepNight(date: day(offset), start: end.addingTimeInterval(-hours * 3600), end: end,
                          asleep: hours * 3600, deep: 0, rem: 0, core: hours * 3600, awake: 0)
    }

    /// 120 alternating baseline days, then a bad morning: low HRV, high resting HR, fast breathing, short sleep.
    static var recovery: HealthSnapshot {
        HealthSnapshot(
            hrv: series(-120...0) { $0 == 0 ? 40 : ($0 % 2 == 0 ? 50 : 60) },
            restingHR: series(-120...0) { $0 == 0 ? 58 : ($0 % 2 == 0 ? 50 : 54) },
            respiratoryRate: series(-120...0) { $0 == 0 ? 17 : ($0 % 2 == 0 ? 14 : 15) },
            sleep: (-120...0).map { night($0, hours: $0 == 0 ? 6 : ($0 % 2 == 0 ? 7 : 8)) }
        )
    }
}
