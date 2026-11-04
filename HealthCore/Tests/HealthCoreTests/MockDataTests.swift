#if DEBUG
import Foundation
import Testing
@testable import HealthCore

@Suite struct MockDataTests {
    @Test func deterministicForSameSeed() {
        let a = MockData.snapshot(endingOn: Fixture.today)
        let b = MockData.snapshot(endingOn: Fixture.today)
        #expect(a.hrv == b.hrv)
        #expect(a.weight == b.weight)
        #expect(a.workouts.map(\.id) == b.workouts.map(\.id))
        #expect(MockData.snapshot(endingOn: Fixture.today, seed: 7).hrv != a.hrv)
    }

    @Test func feedsEveryEngine() {
        let s = MockData.snapshot(endingOn: Fixture.today)
        #expect(s.hrv.count == 180)
        #expect(s.hrv.last?.date == Fixture.today)

        let r = RecoveryEngine.evaluate(s, day: Fixture.today)
        #expect(r.score != nil)
        #expect(r.personalZones)

        let load = LoadEngine.evaluate(s, day: Fixture.today)
        #expect(load.acwr != nil)
        #expect(load.cadenceDays == 2)
        #expect(!s.naps.isEmpty)
        #expect(s.profile.age(on: Fixture.today) == 21)
        #expect(VitalsEngine.check(s, day: Fixture.today).checks.count == 6)
        let t = TrainingEngine.evaluate(s, day: Fixture.today, recovery: r.score)
        #expect(t.tau != nil)
        #expect(t.fitness != nil)
        #expect(s.workouts.allSatisfy { $0.heartRate != nil && $0.effort != nil })

        let lifts = MockData.lifts(matching: s.workouts)
        #expect(lifts.count == s.workouts.filter(\.isStrength).count)
        #expect(s.workouts.filter(\.isStrength).allSatisfy { LiftingEngine.session(for: $0, in: lifts) != nil })
        let squat = LiftingEngine.progress(lifts, endingOn: Fixture.today).first { $0.name == "Squat (Barbell)" }
        #expect((squat?.change ?? 0) > 0)

        let body = BodyEngine.evaluate(s, day: Fixture.today)
        #expect((body.ratePerWeek ?? 0) > 0)

        let n = NutritionEngine.evaluate(s, day: Fixture.today)
        #expect(n.daysLogged > 0)
        #expect(n.expenditureIsAdaptive)
        #expect(n.meals != nil)
        #expect(n.avgFiber != nil)
        #expect(SleepEngine.summarize(s, day: Fixture.today, needHours: 8).lastNight != nil)
    }

    @Test func normalsHaveUnitVariance() {
        var rng = SplitMix64(seed: 1)
        let x = (0..<20_000).map { _ in rng.normal() }
        #expect(abs(Stats.mean(x) ?? 1) < 0.03)
        #expect(abs((Stats.sd(x) ?? 0) - 1) < 0.03)
    }
}
#endif
