import Foundation
import Testing
@testable import HealthCore

@Suite struct RecoveryTests {
    @Test func badMorningScoreAndZScores() {
        let r = RecoveryEngine.evaluate(Fixture.recovery, day: Fixture.today)
        #expect(close(r.score, 0.03160518577242739))
        #expect(close(r.hrvZ, -3.4189497632248766))
        #expect(close(r.rhrZ, 2.9748949561287037))
        #expect(close(r.rrZ, 4.958158260214506))
        #expect(close(r.hrvTrendZ, -3.4189497632249397))
        #expect(r.rr == 17)
        #expect(r.hrv == 40)
        #expect(r.rhr == 58)
        #expect(r.sleepHours == 6)
    }

    @Test func personalZonesFromLast30Days() {
        let r = RecoveryEngine.evaluate(Fixture.recovery, day: Fixture.today)
        #expect(r.personalZones)
        #expect(close(r.low, 34.58118067940632))
        #expect(close(r.high, 65.41881932059378))
    }

    @Test func everyGateFires() {
        let r = RecoveryEngine.evaluate(Fixture.recovery, day: Fixture.today)
        #expect(r.zone == .recover)
        #expect(r.reasons == [
            "Score is under the absolute floor of 20.",
            "HRV is 3.4 SD below your baseline.",
            "Your 7-day HRV average has dropped below your normal range.",
            "Resting HR is 3.0 SD above your baseline.",
            "Breathing rate is 5.0 SD above your baseline.",
            "Last night was in your shortest 10% of nights.",
        ])
    }

    @Test func gateCapsAGoodScore() {
        // Great HRV, but resting HR 1 to 2 SD high must cap the zone at moderate.
        var s = Fixture.recovery
        s.hrv = Fixture.series(-120...0) { $0 == 0 ? 80 : ($0 % 2 == 0 ? 50 : 60) }
        s.restingHR = Fixture.series(-120...0) { $0 == 0 ? 55.5 : ($0 % 2 == 0 ? 50 : 54) }
        s.sleep = (-120...0).map { Fixture.night($0, hours: $0 % 2 == 0 ? 7 : 8) }
        s.respiratoryRate = []
        let r = RecoveryEngine.evaluate(s, day: Fixture.today)
        #expect((r.score ?? 0) > r.high)
        #expect(r.zone == .moderate)
        #expect(r.reasons.contains { $0.hasPrefix("Resting HR is 1.") })
    }

    @Test func missingInputsRedistributeWeight() {
        // Only resting HR: its weight renormalizes to 1, so score = 100·Φ(−zRHR).
        let s = HealthSnapshot(restingHR: Fixture.recovery.restingHR)
        let raw = RecoveryEngine.rawScore(on: Fixture.today, s)
        #expect(raw?.hrvZ == nil)
        #expect(close(raw?.score, 0.14654444574185238))
    }

    @Test func missingBreathingRateRenormalizes() {
        var s = Fixture.recovery
        s.respiratoryRate = []
        #expect(close(RecoveryEngine.rawScore(on: Fixture.today, s)?.score, 0.05846563103045784))
    }

    @Test func needsFourteenBaselineDays() {
        let s = HealthSnapshot(
            hrv: Fixture.series(-13...0) { _ in 55 },
            restingHR: Fixture.series(-13...0) { _ in 52 }
        )
        let r = RecoveryEngine.evaluate(s, day: Fixture.today)
        #expect(r.score == nil)
        #expect(r.zone == nil)
        #expect(r.reasons.first?.hasPrefix("Needs 14 nights") == true)
    }

    @Test func historyHasOneScorePerScorableDay() {
        let h = RecoveryEngine.history(Fixture.recovery, days: 31, endingOn: Fixture.today)
        #expect(h.count == 31)
        #expect(h.last?.date == Fixture.today)
    }

    @Test func driversAddUpToTheScore() {
        let r = RecoveryEngine.evaluate(Fixture.recovery, day: Fixture.today)
        #expect(r.drivers.count == 4)
        let sum = r.drivers.reduce(0) { $0 + $1.contribution }
        #expect(close(r.score, 100 * Stats.normalCDF(sum)))      // exact, not approximate
        #expect(r.drivers.first?.input == .hrv)                    // biggest weight and a bad morning
        #expect(r.drivers.allSatisfy { $0.goodZ < 0 })             // every signal is worse than normal
        let hrv = r.drivers.first { $0.input == .hrv }
        #expect(hrv?.value == 40)
        #expect(close(hrv?.typical, (50.0 * 60).squareRoot()))   // geometric mean of alternating 50 and 60
    }

    @Test func shapleyBreakdownMatchesReference() {
        let r = RecoveryEngine.evaluate(Fixture.recovery, day: Fixture.today)
        let b = Dictionary(uniqueKeysWithValues: RecoveryEngine.breakdown(r.drivers).map { ($0.input, $0.points) })
        #expect(close(b[.hrv], -24.480963708934137))
        #expect(close(b[.restingHR], -9.828285276164545))
        #expect(close(b[.breathing], -8.232680063782963))
        #expect(close(b[.sleep], -7.426465765345928))
        #expect(close(r.score, 50 + b.values.reduce(0, +)))          // efficiency: adds up to score minus 50
        #expect(close(RecoveryEngine.whatIf(r.drivers, normal: .hrv), 6.214309653794469))
    }
}
