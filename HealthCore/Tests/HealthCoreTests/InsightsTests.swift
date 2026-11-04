import Foundation
import Testing
@testable import HealthCore

@Suite struct InsightsTests {
    typealias F = Fixture

    // Must match golden.py
    static let i = (0..<90).map(Double.init)
    static let x = i.map { sin(0.7 * $0) + ($0.truncatingRemainder(dividingBy: 7) == 1 ? 0.3 : 0) + 0.02 * $0 }
    static let s = i.map { 7 + sin(0.3 * $0) }
    static let y = (0..<90).map { k in
        0.5 * x[k] + cos(1.3 * i[k]) + (k % 7 == 5 ? 0.4 : 0) - 0.3 * s[k]
    }
    static let weekday = (0..<90).map { $0 % 7 + 1 }

    @Test func partialCorrelationMatchesReference() throws {
        let c = try #require(InsightsEngine.correlate(x: Self.x, y: Self.y, weekday: Self.weekday, covariates: [Self.s], isFlag: false))
        #expect(close(c.r, 0.4871722546069038))
        #expect(close(c.nEff, 43.88573037353309))
        #expect(close(c.ci.lowerBound, 0.22206149095304598))
        #expect(close(c.ci.upperBound, 0.6852091649449221))
        #expect(close(c.p, 0.0006642537215115762))
        #expect(close(c.threshold, 0.9740960714647172))
        #expect(close(c.lowMean, -1.9321348541019792))
        #expect(close(c.highMean, -1.23592591611955))

        let w = try #require(InsightsEngine.correlate(x: Self.x, y: Self.y, weekday: Self.weekday, covariates: [], isFlag: false))
        #expect(close(w.r, 0.4869971458212738))
        #expect(close(w.nEff, 40.493709726585394))
        #expect(close(w.p, 0.0011209753324183946))
    }

    @Test func benjaminiHochbergMatchesScipy() {
        let q = Stats.benjaminiHochberg([0.01, 0.04, 0.03, 0.20, 0.002])
        for (a, b) in zip(q, [0.025, 0.05, 0.05, 0.2, 0.01]) { #expect(close(a, b)) }
    }

    @Test func smallSamplesAreNotTested() {
        #expect(InsightsEngine.correlate(x: Array(Self.x.prefix(29)), y: Array(Self.y.prefix(29)),
                                         weekday: Array(Self.weekday.prefix(29)), covariates: [], isFlag: false) == nil)
        // 10 yes days out of 90 is below the 15 per half minimum
        let flag = (0..<90).map { $0 < 10 ? 1.0 : 0 }
        #expect(InsightsEngine.correlate(x: flag, y: Self.y, weekday: Self.weekday, covariates: [], isFlag: true) == nil)
    }

    @Test func featureDayLinesUpWithTheNextMorning() throws {
        // Tag on day D drops HRV on morning D + 1 by 10 ms, every third day
        let tagged = Set((-89...(-1)).filter { $0 % 3 == 0 })
        let snapshot = HealthSnapshot(hrv: F.series(-89...0) { tagged.contains($0 - 1) ? 50 : 60 + Double(abs($0) % 2) })
        let tags = (-89...(-1)).map { (day: F.day($0), tags: tagged.contains($0) ? ["Alcohol"] : ["Sauna"]) }
        let features = InsightsEngine.features(snapshot, training: [], lifts: [], tags: tags)
        let alcohol = try #require(features.first { $0.id == "tag:Alcohol" })
        let insight = try #require(InsightsEngine.test(alcohol, InsightsEngine.outcomes(snapshot, recovery: [])[1], lag: 0, sleepHours: []))
        #expect(insight.r < -0.9)
        #expect(close(insight.highMean, 50))
        #expect(!insight.helps)
        let later = try #require(InsightsEngine.test(alcohol, InsightsEngine.outcomes(snapshot, recovery: [])[1], lag: 1, sleepHours: []))
        #expect(abs(later.r) < abs(insight.r))
    }

    @Test func mockLiftingShowsUpInNextMorningHRV() {
        let s = MockData.snapshot(endingOn: F.today)
        let training = TrainingEngine.evaluate(s, day: F.today, recovery: nil)
        let report = InsightsEngine.report(s, recovery: RecoveryEngine.history(s, days: 120, endingOn: F.today),
                                           training: training.days, lifts: MockData.lifts(matching: s.workouts), tags: [])
        #expect(report.tested > 50)
        let lifted = report.findings.first { $0.feature.id == "lifted" && $0.outcome.id == "hrv" }
        #expect(lifted?.lag == 0)
        #expect((lifted?.r ?? 0) < 0)
    }

    @Test func weekAgainstTheFourBefore() {
        let v = F.series(-34...0) { $0 > -7 ? 70 : 60 }
        let c = WeeklyReport.compare(v, endingOn: F.today)
        #expect(c.thisWeek == 70)
        #expect(c.usual == 60)
        #expect(c.change == 10)
    }

    @Test func weeklyMeansStartOnMonday() {
        // Fixture today is Saturday 1 Aug 2026: Mon 27 Jul to Sat 1 Aug is one week, the Sunday before ends the last
        let v = F.series(-6...0) { Double($0) }
        let w = Weekly.means(v)
        #expect(w.count == 2)
        #expect(w[0].value == -6)
        #expect(w[1].value == -2.5)
        #expect(w[1].date == F.day(-5))
    }

    @Test func contextIsAveragedPerHalfAndMechanicalPairsAreSkipped() throws {
        // Late bedtime (60 min after midnight) on even days with a late wake (600), early (−60) with early wake (480)
        let days = -90...(-2)   // 45 late nights, 44 early: the median is the late value, so the halves are 44 and 45
        let bed = days.map { DailyValue(date: F.day($0), value: $0 % 2 == 0 ? 60 : -60) }
        let wake = days.map { DailyValue(date: F.day($0), value: $0 % 2 == 0 ? 600 : 480) }
        let f = InsightFeature(id: "bedtime", name: "Bedtime", kind: .clock, controlForSleep: false, values: bed,
                               context: InsightContext(name: "waking", kind: .clock, values: wake))
        let o = InsightOutcome(id: "hrv", name: "HRV", unit: "ms", higherIsBetter: true,
                               values: (-89...(-1)).map { DailyValue(date: F.day($0), value: ($0 - 1) % 2 == 0 ? 50 : 60 + Double(abs($0) % 3)) })
        let i = try #require(InsightsEngine.test(f, o, lag: 0, sleepHours: []))
        #expect(i.lowContext == 480)
        #expect(i.highContext == 600)
        let s = HealthSnapshot(sleep: (-89...0).map { F.night($0, hours: 7) })
        let report = InsightsEngine.report(s, recovery: [], training: [], lifts: [], tags: [])
        #expect(!report.all.contains { $0.feature.id == "bedtime" && $0.outcome.id == "efficiency" && $0.lag == 0 })
    }
}
