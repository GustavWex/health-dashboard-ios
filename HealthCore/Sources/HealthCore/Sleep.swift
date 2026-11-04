import Foundation

public struct SleepSummary: Sendable {
    public let lastNight: SleepNight?     // the night that ended today, if any
    public let latestNight: SleepNight?   // most recent night up to today; shown before tonight's sleep exists
    public let avg7: Double?
    public let debt7: Double
    public let consistencyMin: Double?   // SD of sleep midpoint
    public let needHours: Double
}

public enum SleepEngine {
    /// Sleep debt is the sum of nightly shortfalls against `needHours` over 7 nights (Athlytic style).
    /// Consistency is the SD of the sleep midpoint in minutes, a design choice rather than a published index.
    public static func summarize(_ s: HealthSnapshot, day: Date, needHours: Double) -> SleepSummary {
        let cal = Calendar.current
        let last = s.sleep.first { cal.isDate($0.date, inSameDayAs: day) }
        let start = cal.date(byAdding: .day, value: -6, to: day)!
        let week = s.sleep.filter { $0.date >= start && $0.date <= day }
        let hours = week.map { $0.asleep / 3600 }
        let debt = hours.reduce(0) { $0 + max(0, needHours - $1) }
        let midpoints = week.map { n -> Double in
            let mid = n.start.addingTimeInterval(n.end.timeIntervalSince(n.start) / 2)
            let c = cal.dateComponents([.hour, .minute], from: mid)
            let mins = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return (mins + 720).truncatingRemainder(dividingBy: 1440) // minutes since noon, avoids midnight wrap
        }
        return SleepSummary(
            lastNight: last,
            latestNight: s.sleep.last { $0.date <= day },
            avg7: Stats.mean(hours),
            debt7: debt,
            consistencyMin: week.count >= 4 ? Stats.sd(midpoints) : nil,
            needHours: needHours
        )
    }
}

// MARK: - Grouping raw samples into nights

public enum SleepStage: Sendable {
    case inBed, awake, core, deep, rem, unspecified
}

/// One sleep analysis sample, stripped of HealthKit types.
public struct SleepSegment: Sendable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage
    public let fromWatch: Bool

    public init(start: Date, end: Date, stage: SleepStage, fromWatch: Bool) {
        self.start = start
        self.end = end
        self.stage = stage
        self.fromWatch = fromWatch
    }
}

public enum SleepGrouping {
    /// Gap that still counts as the same sleep session, so a short wake in the night doesn't split it.
    public static let maxGap: TimeInterval = 2 * 3600
    /// Shortest main sleep that counts as a night.
    public static let minNight: TimeInterval = 3600
    /// Shortest sleep that counts as a nap.
    public static let minNap: TimeInterval = 10 * 60
    /// Wake bouts closer together than this merge into one, so a wake that the watch splits in two counts once.
    public static let awakeningMergeGap: TimeInterval = 2 * 60
    /// Shortest merged wake bout that counts as an awakening. The watch marks every brief stir as awake, which
    /// makes raw counts twitchy. Calibrated on a real night against Withings: 15 raw wake
    /// samples, Withings counted 7 interruptions; 2 min gave 6 and 3 min gave 5, so 2 min is the closest.
    /// Wake after sleep onset matched Withings to the minute (98 vs 97 min).
    public static let minAwakening: TimeInterval = 2 * 60

    /// Groups samples into nights and naps, keyed by wake-up day.
    ///
    /// 1. Asleep and awake samples from all sources are clustered into sessions; gaps up to `maxGap` join.
    /// 2. Per session, Apple Watch samples win when present, so iPhone or other sources don't double count,
    ///    but a night with no watch data still counts.
    /// 3. A session ending before 18:00 belongs to that day, later ones to the next day.
    /// 4. Per day, the session with most sleep is the night. Other sessions are naps. A main session under
    ///    3 h that starts between 09:00 and 18:00 is a nap too, so a day with no night doesn't turn a nap into one.
    /// No Sleep Focus is needed: grouping only looks at the samples, not at a schedule.
    public static func group(_ segments: [SleepSegment]) -> (nights: [SleepNight], naps: [Nap]) {
        let cal = Calendar.current
        let relevant = segments.filter { $0.stage != .inBed && $0.end > $0.start }.sorted { $0.start < $1.start }

        var sessions: [[SleepSegment]] = []
        var sessionEnd = Date.distantPast
        for seg in relevant {
            if !sessions.isEmpty, seg.start.timeIntervalSince(sessionEnd) <= maxGap {
                sessions[sessions.count - 1].append(seg)
            } else {
                sessions.append([seg])
            }
            sessionEnd = max(sessionEnd, seg.end)
        }

        let summaries: [SleepNight] = sessions.compactMap { all in
            let watch = all.filter(\.fromWatch)
            let items = watch.isEmpty ? all : watch
            var deep = 0.0, rem = 0.0, core = 0.0, unspecified = 0.0, awake = 0.0
            var asleepItems: [SleepSegment] = []
            for s in items {
                let d = s.end.timeIntervalSince(s.start)
                switch s.stage {
                case .deep: deep += d; asleepItems.append(s)
                case .rem: rem += d; asleepItems.append(s)
                case .core: core += d; asleepItems.append(s)
                case .unspecified: unspecified += d; asleepItems.append(s)
                case .awake: awake += d
                case .inBed: break
                }
            }
            guard let start = asleepItems.map(\.start).min(), let end = asleepItems.map(\.end).max() else { return nil }
            let day = cal.startOfDay(for: end.addingTimeInterval(6 * 3600))
            let bouts = wakeBouts(items.filter { $0.stage == .awake }, within: start...end)
            return SleepNight(date: day, start: start, end: end, asleep: deep + rem + core + unspecified,
                              deep: deep, rem: rem, core: core, awake: awake,
                              awakenings: bouts.filter { $0.duration >= minAwakening }.count,
                              waso: bouts.reduce(0) { $0 + $1.duration },
                              stages: items.sorted { $0.start < $1.start }
                                  .map { StageInterval(start: $0.start, end: $0.end, stage: $0.stage) })
        }

        var nights: [SleepNight] = []
        var naps: [Nap] = []
        for (_, daySessions) in Dictionary(grouping: summaries, by: \.date) {
            let sorted = daySessions.sorted { $0.asleep > $1.asleep }
            var rest = sorted.dropFirst()
            if let main = sorted.first {
                let startHour = cal.component(.hour, from: main.start)
                let looksLikeNap = main.asleep < 3 * 3600 && (9..<18).contains(startHour)
                if main.asleep >= minNight && !looksLikeNap {
                    nights.append(main)
                } else {
                    rest = sorted[...]
                }
            }
            // A nap belongs to the day it started, even one running past 18:00.
            naps += rest.filter { $0.asleep >= minNap }
                .map { Nap(date: cal.startOfDay(for: $0.start), start: $0.start, end: $0.end, asleep: $0.asleep) }
        }
        return (nights.sorted { $0.date < $1.date }, naps.sorted { $0.start < $1.start })
    }

    /// Wake bouts strictly inside the sleep window, with bouts less than `mergeGap` apart joined into one.
    /// Wake before falling asleep or after the final wake-up is not an awakening.
    public static func wakeBouts(_ awake: [SleepSegment], within window: ClosedRange<Date>,
                                 mergeGap: TimeInterval = awakeningMergeGap) -> [DateInterval] {
        var bouts: [DateInterval] = []
        for seg in awake.sorted(by: { $0.start < $1.start })
        where seg.start > window.lowerBound && seg.end < window.upperBound {
            if let last = bouts.last, seg.start.timeIntervalSince(last.end) <= mergeGap {
                bouts[bouts.count - 1] = DateInterval(start: last.start, end: max(last.end, seg.end))
            } else {
                bouts.append(DateInterval(start: seg.start, end: seg.end))
            }
        }
        return bouts
    }

    /// Wake bouts of a stored night, for the calibration view and the hypnogram.
    public static func wakeBouts(of night: SleepNight, mergeGap: TimeInterval = awakeningMergeGap) -> [DateInterval] {
        let awake = night.stages.filter { $0.stage == .awake }
            .map { SleepSegment(start: $0.start, end: $0.end, stage: .awake, fromWatch: true) }
        return wakeBouts(awake, within: night.start...night.end, mergeGap: mergeGap)
    }

    static func awakenings(_ awake: [SleepSegment], within window: ClosedRange<Date>,
                           minDuration: TimeInterval = minAwakening) -> Int {
        wakeBouts(awake, within: window).filter { $0.duration >= minDuration }.count
    }
}

public enum Overnight {
    /// Window around the main sleep that still counts as overnight, for readings taken just before
    /// falling asleep or just after waking.
    public static let margin: TimeInterval = 30 * 60

    /// Mean of the readings taken during each night's sleep, keyed to the wake-up day. Used for HRV,
    /// respiratory rate and blood oxygen, which swing with movement and stress during the day.
    /// Days with no recorded night fall back to a clock window: readings from 21:00 count toward the
    /// next morning, readings before 10:00 toward that morning.
    public static func daily(_ readings: [Reading], nights: [SleepNight]) -> [DailyValue] {
        let cal = Calendar.current
        let windows = nights.sorted { $0.start < $1.start }
        let nightDays = Set(nights.map(\.date))
        var buckets: [Date: [Double]] = [:]

        for r in readings {
            if let night = containing(r.date, windows) {
                buckets[night.date, default: []].append(r.value)
                continue
            }
            let hour = cal.component(.hour, from: r.date)
            let dayStart = cal.startOfDay(for: r.date)
            let day: Date
            if hour < 10 {
                day = dayStart
            } else if hour >= 21 {
                day = cal.date(byAdding: .day, value: 1, to: dayStart)!
            } else {
                continue
            }
            // On days with a recorded night, a reading outside it was taken awake.
            if !nightDays.contains(day) { buckets[day, default: []].append(r.value) }
        }
        return buckets
            .map { DailyValue(date: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    /// Only the readings taken during one of the nights (with the margin), for per-night charts.
    public static func inside(_ readings: [Reading], nights: [SleepNight]) -> [Reading] {
        let windows = nights.sorted { $0.start < $1.start }
        return readings.filter { containing($0.date, windows) != nil }
    }

    /// Binary search for the night whose window holds `date`. Nights never overlap.
    private static func containing(_ date: Date, _ windows: [SleepNight]) -> SleepNight? {
        var lo = 0, hi = windows.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let w = windows[mid]
            if date < w.start.addingTimeInterval(-margin) {
                hi = mid - 1
            } else if date > w.end.addingTimeInterval(margin) {
                lo = mid + 1
            } else {
                return w
            }
        }
        return nil
    }
}
