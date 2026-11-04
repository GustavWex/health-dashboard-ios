import Foundation
import Testing
@testable import HealthCore

@Suite struct TrainingTests {
    typealias F = Fixture

    /// 30-minute session, one sample per minute climbing from 100 to 158 bpm. Must match golden.py.
    static let workout = WorkoutSummary(id: UUID(), start: F.at(0, 7), duration: 30 * 60, name: "Strength",
                                        isStrength: true, energy: nil)
    static let readings = (0..<30).map { Reading(date: F.at(0, 7, $0), value: 100 + 2 * Double($0)) }

    static var snapshot: HealthSnapshot {
        HealthSnapshot(restingHR: F.series(-29...0) { _ in 50 },
                       profile: Profile(birthDate: F.cal.date(byAdding: .year, value: -21, to: F.today), sex: .male))
    }

    @Test func profileUsesTanakaUnlessObservedIsHigher() {
        let p = TrainingEngine.profile(Self.snapshot, day: F.today, observedMax: 158)
        #expect(p?.rest == 50)
        #expect(close(p?.max, 193.3))
        #expect(close(TrainingEngine.profile(Self.snapshot, day: F.today, observedMax: 201)?.max, 201))
    }

    @Test func trimpAndZonesMatchReference() {
        let male = HeartRateProfile(rest: 50, max: 193.3, sex: .male)
        let hr = TrainingEngine.analyze(Self.readings, end: Self.workout.end, profile: male)
        #expect(close(hr?.trimp, 32.907857168422794))
        #expect(hr?.zoneMinutes == [7, 8, 4, 0, 0])
        #expect(hr?.max == 158)
        #expect(close(hr?.average, 129))

        let female = HeartRateProfile(rest: 50, max: 193.3, sex: .female)
        #expect(close(TrainingEngine.analyze(Self.readings, end: Self.workout.end, profile: female)?.trimp, 38.04312073757337))
    }

    @Test func gapsAreCappedAtTwoMinutes() {
        let p = HeartRateProfile(rest: 50, max: 190, sex: .male)
        let gap = [Reading(date: F.at(0, 7), value: 150)]
        let short = TrainingEngine.analyze(gap, end: F.at(0, 7, 2), profile: p)?.trimp ?? 0
        let long = TrainingEngine.analyze(gap, end: F.at(0, 8), profile: p)?.trimp ?? 1
        #expect(close(short, long))
    }

    @Test func enrichMatchesEffortAndRecovery() {
        let out = TrainingEngine.enrich(
            [Self.workout], heartRate: Self.readings,
            effort: [Reading(date: Self.workout.end.addingTimeInterval(300), value: 7)],
            estimatedEffort: [Reading(date: Self.workout.end, value: 5)],
            hrRecovery: [Reading(date: Self.workout.end.addingTimeInterval(120), value: 25)],
            snapshot: Self.snapshot, day: F.today)
        let w = out[0]
        #expect(close(w.heartRate?.trimp, 32.907857168422794))
        #expect(w.effort == 7)
        #expect(!w.effortIsEstimate)
        #expect(w.hrRecovery == 25)
        #expect(close(TrainingEngine.srpe(w), 210))
    }

    @Test func estimatedEffortIsTheFallback() {
        let out = TrainingEngine.enrich([Self.workout], heartRate: [], effort: [],
                                        estimatedEffort: [Reading(date: Self.workout.end, value: 5)],
                                        hrRecovery: [], snapshot: Self.snapshot, day: F.today)
        #expect(out[0].effort == 5)
        #expect(out[0].effortIsEstimate)
        #expect(out[0].heartRate == nil)
    }

    @Test func fitnessFatigueMatchesReference() {
        let loads = (0..<60).map { $0 % 2 == 1 ? 100.0 : 0 }
        let f = TrainingEngine.fitnessFatigue(loads)
        #expect(close(f?.fitness, 38.47001546711281))
        #expect(close(f?.fatigue, 53.55521956248761))
    }

    @Test func tauPutsTheMedianDayAtMidScale() {
        let days = [50.0, 60, 70, 80, 90].enumerated().map { i, t in
            TrainingDay(date: F.day(-2 * i), trimp: t, strain: nil, srpe: 0)
        } + [TrainingDay(date: F.day(-1), trimp: 0, strain: nil, srpe: 0)]
        let tau = TrainingEngine.calibrateTau(days, endingOn: F.today)
        #expect(close(tau, 100.98865286222744))
        #expect(close(TrainingEngine.strain(trimp: 70, tau: tau ?? 1), 10.5))
        #expect(TrainingEngine.calibrateTau(Array(days.prefix(4)), endingOn: F.today) == nil)
    }

    @Test func weeklyActivityAgainstUsual() {
        let w = { (offset: Int, name: String, minutes: Double) in
            WorkoutSummary(id: UUID(), start: F.at(offset, 8), duration: minutes * 60, name: name, isStrength: false, energy: nil)
        }
        let workouts = [w(0, "Run", 30), w(-3, "Run", 30), w(-10, "Run", 40), w(-20, "Strength", 60)]
        let lines = ActivityEngine.weekly(workouts, endingOn: F.today)
        let run = lines.first { $0.name == "Run" }
        #expect(run?.count == 2)
        #expect(run?.minutes == 60)
        #expect(run?.usualCount == 0.25)
        #expect(run?.usualMinutes == 10)
        #expect(lines.first { $0.name == "Strength" }?.count == 0)
    }
}
