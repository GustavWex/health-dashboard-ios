import Foundation
import Testing
@testable import HealthCore

@Suite struct LiftingTests {
    typealias F = Fixture

    /// The same file golden.py reads.
    static let sample = try! String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("reference/strong_sample.csv"), encoding: .utf8)

    static var sessions: [LiftSession] { try! StrongCSV.parse(sample) }

    @Test func parsesSessionsNewestFirst() throws {
        let s = Self.sessions
        #expect(s.map(\.name) == ["Push, heavy", "Legs"])
        #expect(s[0].start == F.at(-2, 7, 30))
        #expect(s[0].duration == 3900)
        #expect(s[1].duration == 3480)
        #expect(s[0].sets.count == 4)          // the plank row has no reps
        #expect(s[1].sets.count == 2)          // the rest timer row is skipped
        #expect(s[0].sets[0].isWarmup)
        #expect(s[0].sets[1].rpe == 8)
        #expect(s[0].exercises == ["Bench Press (Barbell)", "Pull Up"])
    }

    @Test func volumeAndE1rmMatchReference() {
        let s = Self.sessions
        #expect(close(LiftingEngine.volumeLoad(s[0].sets), 855))
        #expect(close(LiftingEngine.volumeLoad(s[1].sets), 1360))
        #expect(close(LiftingEngine.bestE1rm(s[0].sets.filter { $0.exercise == "Bench Press (Barbell)" }), 76))
        #expect(LiftingEngine.bestE1rm(s[0].sets.filter { $0.exercise == "Pull Up" }) == nil)
        #expect(close(LiftingEngine.bestE1rm(s[1].sets), 93.33333333333334))
        #expect(LiftingEngine.e1rm(weight: 100, reps: 1) == 100)
        #expect(LiftingEngine.e1rm(weight: 100, reps: 11) == nil)
    }

    @Test func semicolonPoundsAndDecimalComma() throws {
        let csv = "Date;Exercise Name;Weight;Reps;Weight Unit\n2026-07-30 07:30:00;Squat;225;5;lbs\n2026-07-30 07:30:00;Curl;12,5;8;kg\n"
        let s = try StrongCSV.parse(csv)
        #expect(close(LiftingEngine.e1rm(weight: s[0].sets[0].weight, reps: 5), 119.067997125))
        #expect(s[0].sets[1].weight == 12.5)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: StrongImportError.missingColumns(["exercise name", "weight", "reps"])) {
            try StrongCSV.parse("Date,Steps\n2026-07-30,9000\n")
        }
        #expect(throws: StrongImportError.noSets) {
            try StrongCSV.parse("Date,Exercise Name,Weight,Reps\n")
        }
    }

    @Test func durationFormats() {
        #expect(StrongCSV.parseDuration("1h 5m") == 3900)
        #expect(StrongCSV.parseDuration("45m") == 2700)
        #expect(StrongCSV.parseDuration("1h") == 3600)
        #expect(StrongCSV.parseDuration("3600") == 3600)
        #expect(StrongCSV.parseDuration("") == nil)
    }

    @Test func weeklyVolumeAndSets() {
        let weeks = LiftingEngine.weekly(Self.sessions, weeks: 2, endingOn: F.today)
        #expect(weeks.count == 2)
        #expect(close(weeks[1].volumeLoad, 2215))
        #expect(weeks[1].workingSets == 5)
        #expect(weeks[0].volumeLoad == 0)
    }

    @Test func progressComparesWithFourWeeksBefore() {
        let bench = { (day: Int, kg: Double) in
            LiftSession(start: F.at(day, 7), duration: 3600, name: "Push",
                        sets: [LiftSet(exercise: "Bench", weight: kg, reps: 5)])
        }
        let p = LiftingEngine.progress([bench(0, 66), bench(-20, 64), bench(-30, 60)], endingOn: F.today)
        #expect(p[0].sessions == 3)
        #expect(close(p[0].current, 77))
        #expect(close(p[0].change, 7))       // against day -30, the latest at least 28 days back
    }

    @Test func matchesTheOverlappingWorkout() {
        let w = WorkoutSummary(id: UUID(), start: F.at(-2, 7, 35), duration: 3600, name: "Strength", isStrength: true, energy: nil)
        #expect(LiftingEngine.session(for: w, in: Self.sessions)?.name == "Push, heavy")
        let other = WorkoutSummary(id: UUID(), start: F.at(-1, 18), duration: 3600, name: "Run", isStrength: false, energy: nil)
        #expect(LiftingEngine.session(for: other, in: Self.sessions) == nil)
    }
}
