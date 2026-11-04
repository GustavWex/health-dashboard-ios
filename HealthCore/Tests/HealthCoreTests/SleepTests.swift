import Foundation
import Testing
@testable import HealthCore

@Suite struct SleepTests {
    typealias F = Fixture

    static func seg(_ s: Date, _ e: Date, _ stage: SleepStage, watch: Bool = true) -> SleepSegment {
        SleepSegment(start: s, end: e, stage: stage, fromWatch: watch)
    }

    @Test func nightAcrossMidnightIsKeyedToWakeDay() {
        let segments = [
            Self.seg(F.at(-1, 22, 30), F.at(0, 6, 45), .inBed),
            Self.seg(F.at(-1, 23), F.at(0, 2), .core),
            Self.seg(F.at(0, 2), F.at(0, 2, 20), .awake),
            Self.seg(F.at(0, 2, 20), F.at(0, 3, 20), .deep),
            Self.seg(F.at(0, 3, 20), F.at(0, 6, 30), .rem),
            // iPhone estimate of the same night: ignored because watch data exists for it
            Self.seg(F.at(-1, 22), F.at(0, 7), .unspecified, watch: false),
        ]
        let g = SleepGrouping.group(segments)
        #expect(g.nights.count == 1)
        #expect(g.naps.isEmpty)
        let n = g.nights[0]
        #expect(n.date == F.day(0))
        #expect(n.start == F.at(-1, 23))
        #expect(n.end == F.at(0, 6, 30))
        #expect(close(n.core, 3 * 3600))
        #expect(close(n.deep, 3600))
        #expect(close(n.rem, 3 * 3600 + 600))
        #expect(close(n.awake, 1200))
        #expect(close(n.asleep, 7 * 3600 + 600))
        #expect(n.awakenings == 1)
    }

    @Test func shortFragmentsAreNotNights() {
        let g = SleepGrouping.group([Self.seg(F.at(-1, 1), F.at(-1, 1, 50), .core)])
        #expect(g.nights.isEmpty)
    }

    @Test func sourceIsChosenPerNight() {
        // Night 1 has watch data, night 2 only an iPhone estimate. Both must count.
        let segments = [
            Self.seg(F.at(-2, 23), F.at(-1, 7), .core),
            Self.seg(F.at(-2, 22), F.at(-1, 7, 30), .unspecified, watch: false),
            Self.seg(F.at(-1, 23), F.at(0, 7), .unspecified, watch: false),
        ]
        let nights = SleepGrouping.group(segments).nights
        #expect(nights.count == 2)
        #expect(close(nights[0].asleep, 8 * 3600))   // watch, not the longer iPhone estimate
        #expect(close(nights[1].asleep, 8 * 3600))
    }

    @Test func afternoonNapIsKeptApart() {
        let segments = [
            Self.seg(F.at(-1, 23), F.at(0, 6), .core),
            Self.seg(F.at(0, 15, 30), F.at(0, 16, 5), .core),
        ]
        let g = SleepGrouping.group(segments)
        #expect(g.nights.count == 1)
        #expect(close(g.nights[0].asleep, 7 * 3600))
        #expect(g.nights[0].end == F.at(0, 6))
        #expect(g.naps.count == 1)
        #expect(g.naps[0].date == F.day(0))
        #expect(close(g.naps[0].asleep, 35 * 60))
    }

    @Test func napRunningPast18IsDatedByItsStart() {
        let segments = [
            Self.seg(F.at(-1, 23), F.at(0, 7), .core),
            Self.seg(F.at(0, 17, 40), F.at(0, 18, 20), .core),
            Self.seg(F.at(0, 23), F.at(1, 7), .core),
        ]
        let g = SleepGrouping.group(segments)
        #expect(g.nights.map(\.date) == [F.day(0), F.day(1)])
        #expect(g.naps.map(\.date) == [F.day(0)])
    }

    @Test func dayWithOnlyANapHasNoNight() {
        let g = SleepGrouping.group([Self.seg(F.at(0, 14), F.at(0, 15, 30), .core)])
        #expect(g.nights.isEmpty)
        #expect(g.naps.count == 1)
    }

    @Test func shortWakeDoesNotSplitTheNight() {
        let segments = [
            Self.seg(F.at(-1, 23), F.at(0, 2), .core),
            Self.seg(F.at(0, 3, 30), F.at(0, 7), .core),   // 90 min gap, still one night
        ]
        let g = SleepGrouping.group(segments)
        #expect(g.nights.count == 1)
        #expect(close(g.nights[0].asleep, 6.5 * 3600))
        #expect(g.naps.isEmpty)
    }

    @Test func awakeningsCountSeparateBoutsInsideTheNight() {
        let window = F.at(-1, 23)...F.at(0, 7)
        let awake = [
            Self.seg(F.at(-1, 22, 50), F.at(-1, 23), .awake),   // before sleep onset, not an awakening
            Self.seg(F.at(0, 1), F.at(0, 1, 5), .awake),
            Self.seg(F.at(0, 1, 5), F.at(0, 1, 10), .awake),    // touches the previous bout, same awakening
            Self.seg(F.at(0, 4), F.at(0, 4, 15), .awake),
        ]
        #expect(SleepGrouping.awakenings(awake, within: window) == 2)
    }

    @Test func overnightUsesActualSleepWindow() {
        // Slept 01:00 to 09:00. A 00:45 reading is within the 30 min margin; 21:30 and 09:45 are awake.
        let nights = SleepGrouping.group([Self.seg(F.at(0, 1), F.at(0, 9), .core)]).nights
        let readings = [
            Reading(date: F.at(-1, 21, 30), value: 99),
            Reading(date: F.at(0, 0, 45), value: 60),
            Reading(date: F.at(0, 4), value: 40),
            Reading(date: F.at(0, 9, 45), value: 99),
        ]
        let out = Overnight.daily(readings, nights: nights)
        #expect(out.count == 1)
        #expect(out[0].date == F.day(0))
        #expect(close(out[0].value, 50))
    }

    @Test func overnightFallsBackToClockWithoutSleepData() {
        let readings = [
            Reading(date: F.at(-1, 22), value: 60),   // evening counts toward the next morning
            Reading(date: F.at(0, 3), value: 40),
            Reading(date: F.at(0, 9, 59), value: 50),
            Reading(date: F.at(0, 15), value: 99),    // daytime, skipped
            Reading(date: F.at(0, 21), value: 70),    // belongs to tomorrow
        ]
        let out = Overnight.daily(readings, nights: [])
        #expect(out.count == 2)
        #expect(out[0].date == F.day(0))
        #expect(close(out[0].value, 50))
        #expect(out[1].date == F.day(1))
        #expect(out[1].value == 70)
    }

    @Test func latestNightCoversTheHoursBeforeSleeping() {
        var s = F.recovery
        s.sleep.removeLast()   // no night has ended today yet
        let summary = SleepEngine.summarize(s, day: F.today, needHours: 8)
        #expect(summary.lastNight == nil)
        #expect(summary.latestNight?.date == F.day(-1))
    }

    @Test func weeklySummary() {
        let s = SleepEngine.summarize(F.recovery, day: F.today, needHours: 8)
        #expect(close(s.lastNight?.asleep, 6 * 3600))
        #expect(close(s.avg7, 7.285714285714286))
        #expect(close(s.debt7, 5))
        #expect(close(s.consistencyMin, 22.677868380553633))
    }
}
