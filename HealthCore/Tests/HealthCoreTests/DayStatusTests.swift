import Testing
@testable import HealthCore

@Suite struct DayStatusTests {
    @Test func gradesAverageIntoAVerdict() {
        #expect(DayStatus.evaluate(sleepScore: 85, zone: .push, strain: 6, target: 9...13) == .good)       // 2, 2, 2
        #expect(DayStatus.evaluate(sleepScore: 70, zone: .moderate, strain: 6, target: 9...13) == .steady) // 1, 1, 2
        #expect(DayStatus.evaluate(sleepScore: 50, zone: .moderate, strain: 15, target: 9...13) == .takeItEasy) // 0, 1, 0
        #expect(DayStatus.evaluate(sleepScore: nil, zone: nil, strain: nil, target: nil) == nil)
    }

    @Test func poorRecoveryCapsTheDay() {
        // Great sleep and on-target strain average 1.33 with a poor recovery: steady, not good
        #expect(DayStatus.evaluate(sleepScore: 90, zone: .recover, strain: 3, target: 6...10) == .steady)
    }
}
