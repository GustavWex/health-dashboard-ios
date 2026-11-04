import Foundation
import Testing
@testable import HealthCore

@Suite struct ExportTests {
    typealias F = Fixture

    static var table: ExportTable {
        let s = HealthSnapshot(hrv: F.series(-2...0) { 50 + Double($0) },
                               sleep: [F.night(0, hours: 7.5)],
                               weight: F.series(-1...(-1)) { _ in 65.25 },
                               dietaryEnergy: F.series(-1...(-1)) { _ in 2600 },
                               protein: F.series(-2...(-1)) { _ in 140 })     // day -2 has no food log, so no protein
        return DailyExport.table(s, recovery: [], training: [], lifts: [], tags: [(F.day(-1), ["Sauna", "Late, \"big\" meal"])],
                                 needHours: 8, days: 3, endingOn: F.today)
    }

    @Test func oneRowPerDayAligned() {
        let t = Self.table
        let col = { (name: String) in t.columns.firstIndex(of: name)! }
        #expect(t.rows.count == 3)
        #expect(t.rows.allSatisfy { $0.count == t.columns.count })
        #expect(t.rows[2][col("sleep_h")] == .number(7.5))
        #expect(t.rows[2][col("wake")] == .text("07:00"))
        #expect(t.rows[0][col("protein_g")] == .missing)
        #expect(t.rows[1][col("protein_g")] == .number(140))
        #expect(t.rows[1][col("workout_min")] == .number(0))
    }

    @Test func csvQuotesAndFormats() {
        let lines = Self.table.csv.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0].hasPrefix("date,feel,recovery,hrv_ms"))
        #expect(lines[2].contains(",65.25,"))
        #expect(lines[2].hasSuffix("\"Sauna; Late, \"\"big\"\" meal\""))
        #expect(lines.count == 5)   // header, 3 rows, trailing newline
    }

    @Test func jsonUsesNullForMissing() throws {
        let objects = try #require(try JSONSerialization.jsonObject(with: Self.table.json) as? [[String: Any]])
        #expect(objects.count == 3)
        #expect(objects[0]["protein_g"] is NSNull)
        #expect(objects[2]["hrv_ms"] as? Double == 50)
        #expect(objects[0]["date"] as? String == "2026-07-30")
    }
}
