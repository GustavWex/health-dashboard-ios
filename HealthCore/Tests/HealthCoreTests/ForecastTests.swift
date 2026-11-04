import Foundation
import Testing
@testable import HealthCore

@Suite struct ForecastTests {
    typealias F = Fixture

    // Must match golden.py
    static func st(_ j: Int) -> Double { j >= 0 && j % 2 == 0 && j % 10 != 0 ? 1 : 0 }
    static func ot(_ j: Int) -> Double { j >= 0 && j % 7 == 3 ? 1 : 0 }
    static let outcome = (0..<80).map { i in
        DailyValue(date: F.day(i - 79), value: 55 + 8 * sin(0.9 * Double(i)) - 6 * st(i - 1) + 2 * st(i - 2) - 3 * ot(i - 1))
    }
    static let workouts = (0..<80).flatMap { j -> [WorkoutSummary] in
        (st(j) == 1 ? [WorkoutSummary(id: UUID(), start: F.at(j - 79, 8), duration: 3600, name: "Strength", isStrength: true, energy: nil)] : [])
            + (ot(j) == 1 ? [WorkoutSummary(id: UUID(), start: F.at(j - 79, 18), duration: 1800, name: "Run", isStrength: false, energy: nil)] : [])
    }

    @Test func posteriorMatchesReference() throws {
        let m = try #require(ReadinessEngine.fit(Self.outcome, workouts: Self.workouts, name: "Recovery", effectSD: 10))
        #expect(close(m.mu, 53.15343474620386))
        #expect(close(m.posterior.sigma2, 8.341652682589718))
        let expected = [0.5245235897560212, -4.125180337385458, 7.500799357734088, 0.9331994584200667, 1.4723507838386327,
                        -10.639779785054756, -6.262697299706692, -3.4188318942744043, 1.0377625799800718]
        for (a, b) in zip(m.posterior.mean, expected) { #expect(close(a, b)) }
        #expect(close(m.posterior.cov[0][0], 0.006252466958073644))
    }

    @Test func curveFollowsTheRecursion() throws {
        let m = try #require(ReadinessEngine.fit(Self.outcome, workouts: Self.workouts, name: "Recovery", effectSD: 10))
        let c = ReadinessEngine.curve(m, strength: true)
        let expected = [-4.125180337385458, 5.337044958777714, 3.732605438887429, 3.430190387786716, 1.7992157757484868]
        for (a, b) in zip(c.map(\.mean), expected) { #expect(close(a, b)) }
        #expect(c.allSatisfy { $0.low <= $0.high })
    }

    @Test func priorDominatesWithoutData() throws {
        // One row: the posterior barely moves from the prior
        let p = try #require(BayesianRegression.posterior([[1, 0]], [5], priorMean: [0.5, 0], priorSD: [0.001, 0.001], sigma2: 1))
        #expect(abs(p.mean[0] - 0.5) < 0.001)
    }

    @Test func matrixInverse() throws {
        let a = [[4.0, 7], [2, 6]]
        let inv = try #require(Matrix.inverse(a))
        #expect(close(inv[0][0], 0.6))
        #expect(close(inv[0][1], -0.7))
        #expect(Matrix.inverse([[1, 2], [2, 4]]) == nil)
    }

    @Test func meanRevertingSeriesBeatsNaive() {
        // AR(1) around 60 with φ = 0.4: "same as today" is a poor forecast, the model should win
        var rng = SplitMix64(seed: 3)
        var v = 60.0
        let series = (0..<150).map { i -> DailyValue in
            v = 60 + 0.4 * (v - 60) + 8 * rng.normal()
            return DailyValue(date: F.day(i - 149), value: v)
        }
        let skill = ReadinessEngine.backtest(series, workouts: [], effectSD: 10)
        #expect(skill.count == 5)
        #expect(skill.allSatisfy { $0.skill > 0 })
    }

    @Test func planFollowsTheRhythm() {
        let load = LoadResult(todayActive: nil, acwr: nil, band: "", typicalWeekdays: [], cadenceDays: 2,
                              sessionsPerWeek: 3.5, lastStrength: F.at(-1, 8), recent: [])
        let plan = ReadinessEngine.plannedStrength(load, from: F.today, days: 5)
        #expect(plan == [F.day(1), F.day(3)])
    }

    @Test func mockForecastIsGated() throws {
        let s = MockData.snapshot(endingOn: F.today)
        let f = try #require(ReadinessEngine.evaluate(RecoveryEngine.history(s, days: 150, endingOn: F.today), workouts: s.workouts,
                                                      name: "Recovery", effectSD: 10, plan: [], today: F.today))
        #expect(f.days.count == f.skill.filter { $0.skill > 0 }.count)
        #expect(f.strengthCurve[0].mean < 0)   // mock lifting lowers the next morning
    }
}
