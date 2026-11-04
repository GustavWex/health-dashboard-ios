import Foundation
import Testing
@testable import HealthCore

@Suite struct WithingsTests {
    typealias F = Fixture

    static func group(_ id: Int, _ date: Date, _ measures: [(type: Int, value: Int, unit: Int)]) -> String {
        let m = measures.map { #"{"type":\#($0.type),"value":\#($0.value),"unit":\#($0.unit)}"# }.joined(separator: ",")
        return #"{"grpid":\#(id),"date":\#(Int(date.timeIntervalSince1970)),"category":1,"measures":[\#(m)]}"#
    }

    static var response: Data {
        let groups = [
            group(1, F.at(-1, 7, 10), [(76, 5234, -2), (77, 3810, -2), (88, 281, -2), (170, 4, 0), (226, 1655, 0)]),
            group(2, F.at(-1, 19), [(76, 5300, -2)]),                     // evening: not the first of the day
            group(3, F.at(0, 7), [(76, 52450, -3), (227, 19, 0)]),
        ].joined(separator: ",")
        return Data(#"{"status":0,"body":{"updatetime":1793360000,"timezone":"Europe/Copenhagen","measuregrps":[\#(groups)],"more":1,"offset":3}}"#.utf8)
    }

    @Test func decodesValueTimesPowerOfTen() throws {
        let page = try WithingsBody.parse(Self.response)
        #expect(page.groups.count == 3)
        #expect(close(page.groups[0].measures[76], 52.34))
        #expect(close(page.groups[2].measures[76], 52.45))
        #expect(page.groups[0].measures[170] == 4)
        #expect(page.more)
        #expect(page.offset == 3)
        #expect(page.updateTime == 1793360000)
    }

    @Test func firstWeighInOfTheDay() throws {
        var s = HealthSnapshot()
        WithingsBody.apply(try WithingsBody.parse(Self.response).groups, to: &s)
        #expect(s.muscleMass.count == 2)
        #expect(close(s.muscleMass[0].value, 52.34))   // 07:10, not the 19:00 reading
        #expect(close(s.bodyWater.first?.value, 38.1))
        #expect(close(s.boneMass.first?.value, 2.81))
        #expect(s.bmr.first?.value == 1655)
        #expect(s.metabolicAge.first?.date == F.today)
    }

    @Test func errorsAndMerging() throws {
        #expect(throws: WithingsError.status(401)) { try WithingsBody.parse(Data(#"{"status":401,"error":"invalid_token"}"#.utf8)) }
        let a = WithingsGroup(id: 1, date: F.at(-1, 7), measures: [76: 50])
        let b = WithingsGroup(id: 1, date: F.at(-1, 7), measures: [76: 51])
        let c = WithingsGroup(id: 2, date: F.at(-2, 7), measures: [76: 49])
        let merged = WithingsBody.merge([a, c], [b])
        #expect(merged.map(\.id) == [2, 1])
        #expect(merged[1].measures[76] == 51)
    }

    @Test func bodyEngineUsesWithingsSeries() {
        var s = HealthSnapshot(weight: F.series(-56...0) { _ in 65 })
        s.muscleMass = F.series(-56...0) { 50 + 0.01 * Double($0 + 56) }
        s.bodyWater = F.series(0...0) { _ in 39 }
        s.visceralFat = F.series(0...0) { _ in 3 }
        let b = BodyEngine.evaluate(s, day: F.today)
        #expect(close(b.muscleMass, 50.56))
        #expect(close(b.muscleRatePerMonth, 0.3))   // 0.01 kg per day
        #expect(close(b.waterPercent, 60))
        #expect(b.visceralFat == 3)
    }
}
