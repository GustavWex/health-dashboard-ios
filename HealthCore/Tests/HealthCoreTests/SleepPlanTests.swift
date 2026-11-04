import Foundation
import Testing
@testable import HealthCore

@Suite struct SleepPlanTests {
    typealias F = Fixture

    @Test func bedtimeStretchesNeedByEfficiency() {
        // 8 h need at 90% efficiency is 8 h 53 min in bed: from 07:40 (460) back to 22:47 (1367)
        #expect(close(SleepPlan.bedtime(wake: 460, needHours: 8, efficiency: 0.9), 1440 + 460 - 480 / 0.9))
        #expect(SleepPlan.wrap(-60) == 1380)
    }

    @Test func wakeDeviationAndScore() {
        let n = SleepNight(date: F.today, start: F.at(-1, 23), end: F.at(0, 8, 20), asleep: 8 * 3600,
                           deep: 0, rem: 0, core: 8 * 3600, awake: 0)
        #expect(SleepPlan.wakeDeviation(n, goal: 460) == 40)    // 08:20 against 07:40
        #expect(SleepPlan.wakeScore(deviation: 20) == 100)
        #expect(close(SleepPlan.wakeScore(deviation: 75), 50))
        #expect(SleepPlan.wakeScore(deviation: -150) == 0)
    }

    @Test func efficiencyAndUsualWakeAreMedians() {
        let nights = (0..<7).map { i in
            SleepNight(date: F.day(-i), start: F.at(-i - 1, 23), end: F.at(-i, 7, i * 5), asleep: 7 * 3600,
                       deep: 0, rem: 0, core: 7 * 3600, awake: 0)
        }
        #expect(close(SleepPlan.usualWake(nights), 435))   // wake times 07:00 to 07:30, median 07:15
        #expect(SleepPlan.efficiency(Array(nights.prefix(4))) == nil)   // needs 5 nights
    }

    @Test func wakeHabitCountsOnTimeMornings() {
        let s = HealthSnapshot(sleep: (-6...0).map { o in
            SleepNight(date: F.day(o), start: F.at(o - 1, 23), end: F.at(o, o == 0 ? 9 : 7, 45), asleep: 8 * 3600,
                       deep: 0, rem: 0, core: 8 * 3600, awake: 0)
        })
        let wake = HabitEngine.evaluate(s, day: F.today, sleepScore: { _ in 80 }, training: nil, recovery: [], weightKg: nil,
                                        goalIntake: nil, wakeGoal: 460).first { $0.kind == .wake }
        #expect(wake?.hitsThisWeek == 6)     // 07:45 is 5 min off; today's 09:45 is not
        #expect(wake?.streak == 0)
    }
}
