import Foundation
import Testing
@testable import HealthCore

@Suite struct HabitsTests {
    typealias F = Fixture

    @Test func sleepHitsAtSevenHours() {
        #expect(HabitEngine.sleepDay(F.night(0, hours: 7), score: 80).hit == true)
        #expect(HabitEngine.sleepDay(F.night(0, hours: 6.9), score: 80).hit == false)
    }

    @Test func foodNeedsProteinAndCalories() {
        let s = HealthSnapshot(dietaryEnergy: F.series(-2...(-1)) { $0 == -1 ? 2600 : 3200 },
                               protein: F.series(-2...(-1)) { _ in 110 })   // 110 g at 65 kg is 1.69 g/kg
        #expect(HabitEngine.foodDay(s, on: F.day(-1), weightKg: 65, goalIntake: 2500)?.hit == true)   // 4% over
        #expect(HabitEngine.foodDay(s, on: F.day(-2), weightKg: 65, goalIntake: 2500)?.hit == false)  // 28% over
        #expect(HabitEngine.foodDay(s, on: F.day(-3), weightKg: 65, goalIntake: 2500) == nil)         // not logged
    }

    @Test func streakCountsBackSkippingEmptyDays() {
        let d = { (o: Int, hit: Bool?) in HabitDay(date: F.day(o), score: nil, hit: hit) }
        #expect(HabitEngine.streak([d(-4, false), d(-3, true), d(-2, nil), d(-1, true), d(0, true)]) == 3)
        #expect(HabitEngine.streak([d(-1, true), d(0, false)]) == 0)
    }

    @Test func strengthBuildsSlowlyAndOneMissCostsLittle() {
        let hits = (0..<30).map { HabitDay(date: F.day(-$0), score: nil, hit: true) }
        let built = HabitEngine.strength(hits)
        #expect(close(built, 100 * (1 - pow(29.0 / 30, 30))))     // about 64 after 30 straight days
        let afterMiss = HabitEngine.strength(hits + [HabitDay(date: F.today, score: nil, hit: false)])
        #expect(close(afterMiss, built * 29 / 30))                // a miss keeps 29/30 of it
    }
}
