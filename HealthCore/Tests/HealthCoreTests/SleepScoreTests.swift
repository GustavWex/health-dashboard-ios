import Foundation
import Testing
@testable import HealthCore

@Suite struct SleepScoreTests {
    typealias F = Fixture

    static var snapshot: HealthSnapshot {
        var s = F.recovery
        s.sleepingHR = F.series(-120...0) { $0 == 0 ? 56 : ($0 % 2 == 0 ? 48 : 50) }
        return s
    }

    @Test func regularityIndexMatchesReference() {
        let s = Self.snapshot
        #expect(close(SleepScoreEngine.regularityIndex(nights: s.sleep, naps: [], endingOn: F.today), 90.27777777777777))
    }

    @Test func regularityNeedsFourNights() {
        let nights = (-2...0).map { F.night($0, hours: 8) }
        #expect(SleepScoreEngine.regularityIndex(nights: nights, naps: [], endingOn: F.today) == nil)
    }

    @Test func identicalNightsArePerfectlyRegular() {
        let nights = (-8...0).map { F.night($0, hours: 8) }
        #expect(close(SleepScoreEngine.regularityIndex(nights: nights, naps: [], endingOn: F.today), 100))
    }

    @Test func badMorningScore() {
        let s = Self.snapshot
        let score = SleepScoreEngine.score(s, night: s.sleep.last!, needHours: 8)
        #expect(close(score.score, 53.93518518518518))
        #expect(score.status == .poor)
        #expect(close(score.component(.duration)?.score, 50))
        #expect(close(score.component(.interruptions)?.score, 100))
        #expect(close(score.component(.hrv)?.score, 0))
        #expect(close(score.component(.heartRate)?.score, 0))
        #expect(score.component(.depth) == nil)   // fixture nights have no stage data
        let lost = score.pointsLost
        #expect(close(lost.reduce(0) { $0 + $1.points }, 100 - 53.93518518518518))   // adds up exactly
        let byKind = Dictionary(uniqueKeysWithValues: lost.map { ($0.kind, $0.points) })
        #expect(close(byKind[.hrv], 0.15 * 100 / 0.9))      // part score 0, five parts present (weights sum to 0.9)
        #expect(close(byKind[.duration], 0.30 * 50 / 0.9))
        #expect(close(byKind[.interruptions], 0))
    }

    @Test func wasoCutoffs() {
        func night(waso minutes: Double) -> SleepNight {
            SleepNight(date: F.today, start: F.at(-1, 23), end: F.at(0, 7), asleep: 8 * 3600,
                       deep: 0, rem: 0, core: 8 * 3600, awake: minutes * 60, waso: minutes * 60)
        }
        let s = HealthSnapshot()
        #expect(close(SleepScoreEngine.score(s, night: night(waso: 30), needHours: 8).component(.interruptions)?.score, 100))
        #expect(close(SleepScoreEngine.score(s, night: night(waso: 75), needHours: 8).component(.interruptions)?.score, 50))
        #expect(close(SleepScoreEngine.score(s, night: night(waso: 120), needHours: 8).component(.interruptions)?.score, 0))
    }

    @Test func wakeBoutsMergeAndThreshold() {
        let window = F.at(-1, 23)...F.at(0, 7)
        let awake = [
            SleepTests.seg(F.at(0, 1), F.at(0, 1, 1), .awake),        // 1 min
            SleepTests.seg(F.at(0, 1, 2), F.at(0, 1, 4), .awake),     // 1 min gap: merges into a 4 min bout
            SleepTests.seg(F.at(0, 3), F.at(0, 3, 1), .awake),        // 1 min on its own, below the threshold
            SleepTests.seg(F.at(0, 5), F.at(0, 5, 20), .awake),       // 20 min
        ]
        let bouts = SleepGrouping.wakeBouts(awake, within: window)
        #expect(bouts.map { $0.duration / 60 } == [4, 1, 20])
        #expect(SleepGrouping.awakenings(awake, within: window) == 2)
    }

    @Test func groupedNightKeepsStagesAndWaso() {
        let segments = [
            SleepTests.seg(F.at(-1, 23), F.at(0, 2), .core),
            SleepTests.seg(F.at(0, 2), F.at(0, 2, 20), .awake),
            SleepTests.seg(F.at(0, 2, 20), F.at(0, 7), .deep),
            SleepTests.seg(F.at(0, 7), F.at(0, 7, 10), .awake),      // after the final wake-up, not WASO
        ]
        let n = SleepGrouping.group(segments).nights[0]
        #expect(n.stages.count == 4)
        #expect(close(n.waso, 20 * 60))
        #expect(n.asleepIntervals.count == 2)
    }
}
