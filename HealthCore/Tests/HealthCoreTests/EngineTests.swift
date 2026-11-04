import Foundation
import Testing
@testable import HealthCore

@Suite struct LoadTests {
    typealias F = Fixture

    @Test func acwrFromActiveEnergy() {
        let s = HealthSnapshot(activeEnergy: F.series(-28...0) { $0 == 0 ? 123 : ($0 >= -7 ? 600 : 400) })
        let r = LoadEngine.evaluate(s, day: F.today)
        #expect(close(r.acwr, 1.3333333333333333))
        #expect(r.band == "Building fast")
        #expect(r.todayActive == 123)
    }

    @Test func acwrNeedsThreeWeeks() {
        let s = HealthSnapshot(activeEnergy: F.series(-20...(-1)) { _ in 500 })
        let r = LoadEngine.evaluate(s, day: F.today)
        #expect(r.acwr == nil)
        #expect(r.band == "Needs 3 weeks of data")
    }

    @Test func detectsMondayAndThursdayLifting() {
        var workouts: [WorkoutSummary] = []
        for offset in (-55...(-1)).reversed() {
            let wd = F.cal.component(.weekday, from: F.day(offset))
            if wd == 2 || wd == 5 {
                workouts.append(WorkoutSummary(id: UUID(), start: F.at(offset, 7), duration: 3600,
                                               name: "Strength", isStrength: true, energy: 300))
            } else if wd == 4 {
                workouts.append(WorkoutSummary(id: UUID(), start: F.at(offset, 18), duration: 1800,
                                               name: "Run", isStrength: false, energy: 350))
            }
        }
        let r = LoadEngine.evaluate(HealthSnapshot(workouts: workouts), day: F.today)
        let strength = workouts.filter(\.isStrength).count
        #expect(r.typicalWeekdays == [2, 5])
        #expect(close(r.sessionsPerWeek, Double(strength) / 8))
        #expect(r.recent.count == 5)
        #expect(r.cadenceDays == nil)
    }

    @Test func everyOtherDayIsACadenceNotSevenWeekdays() {
        let workouts = stride(from: -2, through: -56, by: -2).map { offset in
            WorkoutSummary(id: UUID(), start: F.at(offset, 8), duration: 3600, name: "Strength", isStrength: true, energy: nil)
        }
        let r = LoadEngine.evaluate(HealthSnapshot(workouts: workouts), day: F.today)
        #expect(r.typicalWeekdays.isEmpty)
        #expect(r.cadenceDays == 2)
        #expect(r.lastStrength == F.at(-2, 8))
    }
}

@Suite struct DailyTests {
    @Test func firstWeighInOfTheDayWins() {
        let readings = [
            Reading(date: Fixture.at(0, 21), value: 66.4),   // evening, after food and water
            Reading(date: Fixture.at(0, 7), value: 65.2),
            Reading(date: Fixture.at(-1, 7, 5), value: 65.0),
        ]
        let out = Daily.first(readings)
        #expect(out.map(\.date) == [Fixture.day(-1), Fixture.day(0)])
        #expect(out.map(\.value) == [65.0, 65.2])
    }

    @Test func dayLookupBySearch() {
        let series = Fixture.series(-400...0) { Double($0) }
        #expect(series.value(on: Fixture.at(-123, 15)) == -123)
        #expect(series.value(on: Fixture.day(0)) == 0)
        #expect(series.value(on: Fixture.day(-400)) == -400)
        #expect(series.value(on: Fixture.day(1)) == nil)
        #expect([DailyValue]().value(on: Fixture.today) == nil)
    }
}

@Suite struct VitalsTests {
    @Test func restingHRAboveRangeIsFlagged() {
        let v = VitalsEngine.check(Fixture.recovery, day: Fixture.today)
        let rhr = v.checks.first { $0.name == "Resting HR" }
        #expect(close(rhr?.low, 47.96624412728311))
        #expect(close(rhr?.high, 56.03375587271689))
        #expect(rhr?.status == .high)
        #expect(v.checks.first { $0.name == "HRV" }?.status == .low)
        #expect(v.severalUnusual)
        #expect(!v.checks.contains { $0.name == "Blood oxygen" })   // never recorded, so not listed
    }

    @Test func shortHistoryIsLearningAndMissingNightIsNoReading() {
        var s = HealthSnapshot(restingHR: Fixture.series(-5...0) { _ in 52 })
        #expect(VitalsEngine.check(s, day: Fixture.today).checks.first?.status == .learning)
        s.restingHR = Fixture.series(-60...(-1)) { $0 % 2 == 0 ? 50 : 54 }
        #expect(VitalsEngine.check(s, day: Fixture.today).checks.first?.status == .noReading)
    }
}

@Suite struct BodyTests {
    @Test func trendAndRateForLinearGain() {
        let s = HealthSnapshot(
            weight: Fixture.series(-27...0) { 75 + 0.05 * Double($0 + 27) },
            bodyFat: Fixture.series(-1...0) { _ in 0.15 },
            leanMass: Fixture.series(-1...0) { _ in 63 }
        )
        let r = BodyEngine.evaluate(s, day: Fixture.today)
        #expect(close(r.latestWeight, 76.35))
        #expect(close(r.trendWeight, 76.15048357032784))
        #expect(close(r.ratePerWeek, 0.3134644283361831))
        #expect(close(r.bodyFat, 15))
        #expect(r.leanMass == 63)
        #expect(r.leanRatePerMonth == nil)   // needs 3 points
    }
}

@Suite struct NutritionTests {
    @Test func weekOfLogging() {
        let s = HealthSnapshot(
            activeEnergy: Fixture.series(-7...(-1)) { _ in 500 },
            basalEnergy: Fixture.series(-7...(-1)) { _ in 1800 },
            weight: Fixture.series(-1...(-1)) { _ in 75 },
            dietaryEnergy: Fixture.series(-7...(-1)) { $0 == -3 ? 200 : 2500 },   // 200 kcal day is not real logging
            protein: Fixture.series(-7...(-1)) { _ in 150 }
        )
        let r = NutritionEngine.evaluate(s, day: Fixture.today)
        #expect(r.daysLogged == 6)
        #expect(r.avgIntake == 2500)
        #expect(r.avgExpenditure == 2300)
        #expect(r.balance == 200)
        #expect(r.proteinPerKg == 2)
    }
}

@Suite struct AdaptiveTDEETests {
    typealias F = Fixture

    /// Must match golden.py: linear gain of 0.05 kg/day with gaps, intake alternating 2700 and 2950.
    static var snapshot: HealthSnapshot {
        HealthSnapshot(
            weight: (-60...(-1)).filter { $0 % 5 != 0 }.map { DailyValue(date: F.day($0), value: 70 + 0.05 * Double($0 + 60)) },
            dietaryEnergy: F.series(-60...(-1)) { $0 % 7 == 0 ? 0 : ($0 % 2 == 0 ? 2700 : 2950) }
        )
    }

    @Test func matchesReference() {
        let t = NutritionEngine.tdee(Self.snapshot, endingOn: F.day(-1))
        #expect(close(t?.kcal, 2439.873143113328))
        #expect(close(t?.intake, 2825))
        #expect(close(t?.trendPerWeek, 0.3501153244424292))
        #expect(t?.loggedDays == 24)
    }

    @Test func replacesTheWatchEstimateAndSuggestsIntake() {
        let r = NutritionEngine.evaluate(Self.snapshot, day: F.today)
        #expect(r.expenditureIsAdaptive)
        #expect(close(r.avgExpenditure, 2439.873143113328))
        #expect(close(r.suggestedIntake(kgPerWeek: 0.25), 2439.873143113328 + 275))
    }

    @Test func needsFourteenLoggedDays() {
        var s = Self.snapshot
        s.dietaryEnergy = s.dietaryEnergy.filter { $0.date < F.day(-15) || $0.date > F.day(-3) }
        #expect(NutritionEngine.tdee(s, endingOn: F.day(-1)) == nil)
    }
}

@Suite struct MealTimingTests {
    typealias F = Fixture

    static let food = [
        Reading(date: F.at(-2, 21, 40), value: 600),
        Reading(date: F.at(-1, 8), value: 500),
        Reading(date: F.at(-1, 12, 30), value: 700),
        Reading(date: F.at(-1, 12, 50), value: 200),      // 20 min later: same meal
        Reading(date: F.at(-1, 19, 30), value: 900),
    ]

    static func night(_ offset: Int, from start: Date) -> SleepNight {
        SleepNight(date: F.day(offset), start: start, end: F.at(offset, 7), asleep: 7 * 3600,
                   deep: 0, rem: 0, core: 7 * 3600, awake: 0)
    }

    @Test func itemsMergeIntoMeals() {
        let m = NutritionEngine.meals(Self.food)
        #expect(m.count == 4)
        #expect(m[2] == Meal(start: F.at(-1, 12, 30), end: F.at(-1, 12, 50), kcal: 900))
    }

    @Test func hourlyTotalsSitMidHourAndNeighboursJoin() {
        let hourly = [(8, 400.0), (12, 500), (13, 300), (16, 200), (19, 800)].map { Reading(date: F.at(-1, $0.0), value: $0.1) }
        #expect(NutritionEngine.isHourly(hourly))
        #expect(!NutritionEngine.isHourly(Self.food))
        let m = NutritionEngine.meals(hourly)
        #expect(m.count == 4)
        #expect(m[1] == Meal(start: F.at(-1, 12, 30), end: F.at(-1, 13, 30), kcal: 800))
        #expect(m[3].end == F.at(-1, 19, 30))
    }

    @Test func dailySkipsUnloggedDays() {
        let s = HealthSnapshot(dietaryEnergy: F.series(-6...0) { $0 == -3 ? 100 : 2500 },
                               protein: F.series(-6...0) { _ in 140 })
        let d = NutritionEngine.daily(s, days: 7, endingOn: F.today)
        #expect(d.count == 6)
        #expect(d.first?.protein == 140)
        #expect(d.first?.fat == nil)
    }

    @Test func lastMealBeforeSleep() {
        let nights = [Self.night(-1, from: F.at(-2, 23, 30)), Self.night(0, from: F.at(-1, 23))]
        let t = NutritionEngine.mealTiming(NutritionEngine.meals(Self.food), nights: nights)
        #expect(close(t?.lastMealMinutes, (1300 + 1170) / 2))   // 21:40 and 19:30
        #expect(close(t?.gapHours, (110.0 / 60 + 3.5) / 2))
        #expect(t?.lateNights == 1)
        #expect(t?.nights == 2)
        #expect(t?.mealsPerDay == 2)
    }
}

@Suite struct CoachTests {
    @Test func deficitAndLowProteinAreWarnings() {
        let recovery = RecoveryResult(score: 50, zone: .moderate, hrv: nil, hrvZ: nil, rhr: nil, rhrZ: nil,
                                      rr: nil, rrZ: nil, hrvTrendZ: nil, sleepHours: nil, low: 33, high: 66,
                                      personalZones: true, reasons: [])
        let load = LoadResult(todayActive: nil, acwr: 1.6, band: "Spike", typicalWeekdays: [], cadenceDays: 2,
                              sessionsPerWeek: 3.5, lastStrength: Fixture.at(-2, 8), recent: [])
        let nutrition = NutritionResult(daysLogged: 7, avgIntake: 2000, avgExpenditure: 2400, balance: -400,
                                        avgProtein: 90, proteinPerKg: 1.2)
        let c = Coach.advise(recovery: recovery, load: load, nutrition: nutrition, proteinTarget: 1.6, today: Fixture.today)
        #expect(c.headline.hasPrefix("Train, but hold back"))
        #expect(c.notes == [
            "Load ratio is 1.60, a big jump from your last 4 weeks. Don't add volume today.",
            "By your usual rhythm, today is a training day.",
            "You've averaged 400 kcal per day under your estimated burn this week. That can slow recovery.",
            "Protein is 1.2 g/kg against your 1.6 g/kg target.",
        ])
    }
}

@Suite struct ImpactTests {
    @Test func nextMorningDifference() {
        let values: [Double] = [70, 40, 72, 45, 68, 50, 75, 71, 69, 73]
        let scores = zip(-9...0, values).map { DailyValue(date: Fixture.day($0), value: $1) }
        let entries: [(day: Date, tags: [String])] = [
            (Fixture.at(-9, 20), ["Alcohol"]),
            (Fixture.at(-7, 20), ["Alcohol", "Sauna"]),
            (Fixture.at(-5, 20), ["Alcohol", "Sauna"]),
        ]
        let out = ImpactEngine.analyze(entries: entries, scores: scores)
        #expect(out.count == 1)   // Sauna has only 2 days
        #expect(out.first?.tag == "Alcohol")
        #expect(out.first?.count == 3)
        #expect(close(out.first?.delta, -26.14285714285714))
    }
}
