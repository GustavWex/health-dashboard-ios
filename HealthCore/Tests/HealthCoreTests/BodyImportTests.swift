import Foundation
import Testing
@testable import HealthCore

@Suite struct BodyImportTests {
    let utc = TimeZone(identifier: "UTC")!

    func close(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    @Test func withingsExport() throws {
        // Withings web export: fat as mass, hydration in kg
        let csv = """
        Date,"Weight (kg)","Fat mass (kg)","Bone mass (kg)","Muscle mass (kg)","Hydration (kg)",Comments
        "2026-10-30 07:12:40",65.0,9.75,2.9,52.3,38.1,
        """
        let e = try BodyCSV.parse(csv, timeZone: utc)
        #expect(e.count == 1)
        #expect(e[0].values[.weight] == 65)
        #expect(close(e[0].values[.bodyFat], 0.15))            // 9.75 / 65
        #expect(e[0].values[.muscleMass] == 52.3)
        #expect(e[0].values[.bodyWater] == 38.1)
        #expect(e[0].values[.boneMass] == 2.9)
    }

    @Test func renphoSplitDateTimeAndPercentages() throws {
        // Separate date and time columns; water only as a share, muscle in both kg and percent (kg wins)
        let csv = """
        Date,Time,Weight(kg),BMI,Body Fat(%),Fat-free Body Weight(kg),Visceral Fat,Body Water(%),Skeletal Muscle(%),Muscle Mass(kg),Bone Mass(kg),BMR(kcal),Metabolic Age
        2026/10/30,07:30:00,80.0,24.1,20.0,64.0,7,55.0,45.0,60.5,3.1,1750,27
        """
        let e = try BodyCSV.parse(csv, timeZone: utc)[0]
        #expect(e.date == ISO8601DateFormatter().date(from: "2026-10-30T07:30:00Z"))
        #expect(close(e.values[.bodyFat], 0.20))
        #expect(e.values[.leanMass] == 64)
        #expect(e.values[.visceralFat] == 7)
        #expect(close(e.values[.bodyWater], 44))                // 55% of 80 kg
        #expect(e.values[.muscleMass] == 60.5)
        #expect(e.values[.bmr] == 1750)
        #expect(e.values[.metabolicAge] == 27)
    }

    @Test func unitsInCellsAndPounds() throws {
        // Garmin-style: one Time column, units written in the cells, pounds
        let csv = """
        Time,Weight,Body Fat,Skeletal Muscle Mass,Bone Mass,Body Water
        "Oct 30, 2026 7:05 AM",165.0 lbs,18.0 %,70.0 lbs,6.6 lbs,58.0 %
        "Oct 31, 2026 7:10 AM",--,--,--,--,--
        """
        let e = try BodyCSV.parse(csv, timeZone: utc)
        #expect(e.count == 1)                                   // the empty row has no readings
        let kg = 165 * 0.45359237
        #expect(close(e[0].values[.weight], kg))
        #expect(close(e[0].values[.bodyFat], 0.18))
        #expect(close(e[0].values[.muscleMass], 70 * 0.45359237))
        #expect(close(e[0].values[.bodyWater], kg * 0.58))
    }

    @Test func semicolonAndDecimalComma() throws {
        let csv = "Datum;Date;Weight (kg);Fat (%)\nx;30.10.2026;72,4;17,5\n"
        let e = try BodyCSV.parse(csv, timeZone: utc)[0]
        #expect(close(e.values[.weight], 72.4))
        #expect(close(e.values[.bodyFat], 0.175))
    }

    @Test func rejectsFilesWithoutDatesOrMeasures() {
        #expect(throws: BodyImportError.noDateColumn) { try BodyCSV.parse("Weight\n70\n") }
        #expect(throws: BodyImportError.noMeasures) { try BodyCSV.parse("Date,Notes\n2026-10-30,hi\n") }
    }

    @Test func applyFillsOnlyMissingDays() {
        let d1 = Fixture.day(-1), d2 = Fixture.day(0)
        var s = HealthSnapshot()
        s.weight = [DailyValue(date: d1, value: 65)]
        let entries = [BodyEntry(date: d1.addingTimeInterval(7 * 3600), values: [.weight: 99, .muscleMass: 52]),
                       BodyEntry(date: d2.addingTimeInterval(7 * 3600), values: [.weight: 65.2, .muscleMass: 52.1]),
                       BodyEntry(date: d2.addingTimeInterval(19 * 3600), values: [.weight: 66])]
        BodyImport.apply(entries, to: &s)
        #expect(s.weight.map(\.value) == [65, 65.2])           // Apple Health's day stays, first weigh-in per day
        #expect(s.muscleMass.map(\.value) == [52, 52.1])
    }

    @Test func hevyExport() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Push","30 Oct 2026, 07:30","30 Oct 2026, 08:35","","Bench Press (Barbell)",,"",0,"warmup",40,10,,,
        "Push","30 Oct 2026, 07:30","30 Oct 2026, 08:35","","Bench Press (Barbell)",,"",1,"normal",60,8,,,8
        "Push","30 Oct 2026, 07:30","30 Oct 2026, 08:35","","Plank",,"",0,"normal",,,,60,
        """
        let s = try LiftCSV.parse(csv)
        #expect(s.count == 1)
        #expect(s[0].name == "Push")
        #expect(s[0].duration == 3900)
        #expect(s[0].sets.count == 2)                           // the plank has no reps
        #expect(s[0].sets[0].isWarmup)
        #expect(s[0].sets[1].weight == 60 && s[0].sets[1].rpe == 8)
    }

    @Test func liftCSVStillReadsStrong() throws {
        let csv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps\n2026-10-30 07:30:00,Legs,Squat,1,80,5\n"
        #expect(try LiftCSV.parse(csv).first?.sets.first?.weight == 80)
    }
}
