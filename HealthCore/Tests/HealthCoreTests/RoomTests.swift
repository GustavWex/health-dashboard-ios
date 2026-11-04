import Foundation
import Testing
@testable import HealthCore

@Suite struct RoomTests {
    typealias F = Fixture

    static func decay(noise: Double) -> [RoomReading] {
        (0...180).map { i in
            let t = Double(i) / 60
            return RoomReading(date: F.at(0, 8).addingTimeInterval(t * 3600),
                               co2: 420 + 1800 * exp(-0.3 * t) + noise * sin(7 * t))
        }
    }

    @Test func airChangeMatchesReference() throws {
        let a = try #require(RoomEngine.airChange(Self.decay(noise: 15), after: F.at(0, 8)))
        #expect(close(a.ach, 0.3230096692678372))
        #expect(close(a.c0, 2228.9355059664604))
        #expect(a.outdoor == 502)
        #expect(a.points == 181)
    }

    @Test func noiseFreeDecayIsRecovered() throws {
        let a = try #require(RoomEngine.airChange(Self.decay(noise: 0), after: F.at(0, 8)))
        #expect(abs(a.ach - 0.3) < 1e-6)
        #expect(a.outdoor == 420)
    }

    @Test func decayStopsWhenSomeoneComesBack() {
        var r = Self.decay(noise: 0)
        r = r.prefix(15) + r.dropFirst(15).map { RoomReading(date: $0.date, co2: 3000) }
        #expect(RoomEngine.airChange(r, after: F.at(0, 8)) == nil)   // only 15 falling samples
    }

    @Test func nightSummary() throws {
        // Linear climb from 500 to 2500 ppm over an 8 h night, a sample every 5 minutes
        let night = SleepNight(date: F.today, start: F.at(-1, 23), end: F.at(0, 7), asleep: 8 * 3600,
                               deep: 0, rem: 0, core: 8 * 3600, awake: 0)
        let readings = (0...96).map { i in
            RoomReading(date: night.start.addingTimeInterval(Double(i) * 300), co2: 500 + 2000 * Double(i) / 96,
                        temperature: 21, humidity: i < 48 ? 35 : 28)
        }
        let n = try #require(RoomEngine.nights(readings, sleep: [night]).first)
        #expect(close(n.co2Mean, 1500))
        #expect(n.co2Peak == 2500)
        #expect(n.co2AtWake == 2500)
        #expect(close(n.minutesAbove1000, 355))   // 72 samples above, the last counts no time
        #expect(close(n.minutesAbove2000, 115))
        #expect(n.humidityMin == 28)
    }

    @Test func wideCSV() throws {
        let csv = "time,co2,temperature,humidity,lux\n2026-10-30T07:00:00Z,812,21.4,38.2,120\n1793343660,830,21.5,38.0,\n"
        let r = try RoomCSV.parse(csv)
        #expect(r.count == 2)
        #expect(r[0].co2 == 812)
        #expect(r[1].lux == nil)
    }

    @Test func influxLongCSV() throws {
        let csv = """
        #group,false,false,true,false,false
        #datatype,string,long,dateTime:RFC3339,double,string
        ,result,table,_time,_value,_field
        ,_result,0,2026-10-30T07:00:00Z,812,co2
        ,_result,0,2026-10-30T07:00:00Z,21.4,temperature
        ,_result,1,2026-10-30T07:01:00Z,820,co2
        """
        let r = try RoomCSV.parse(csv)
        #expect(r.count == 2)
        #expect(r[0].co2 == 812)
        #expect(r[0].temperature == 21.4)
        #expect(r[1].co2 == 820)
    }

    @Test func notARoomExport() {
        #expect(throws: RoomCSVError.noTimeColumn) { try RoomCSV.parse("a,b\n1,2\n") }
    }
}
