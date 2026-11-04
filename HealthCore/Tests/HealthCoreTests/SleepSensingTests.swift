import Foundation
import Testing
@testable import HealthCore

@Suite struct SleepSensingTests {
    typealias F = Fixture

    static func epochs(from start: Date, _ activity: [Double], hr: [Double]? = nil) -> [MotionEpoch] {
        activity.enumerated().map { i, a in MotionEpoch(time: start.addingTimeInterval(Double(i) * 30), activity: a, heartRate: hr?[i]) }
    }

    @Test func smartWakeOnMovement() {
        let start = F.at(0, 7, 10), end = F.at(0, 7, 40)
        let still = Self.epochs(from: start, [0.004, 0.005, 0.004, 0.005, 0.004])
        #expect(SmartWake.decide(still, windowStart: start, wakeBy: end, now: start.addingTimeInterval(150)) == nil)
        // two of the last three epochs well above 3× the median and the 0.02 g floor
        let stirring = Self.epochs(from: start, [0.004, 0.005, 0.004, 0.005, 0.03, 0.004, 0.04])
        #expect(SmartWake.decide(stirring, windowStart: start, wakeBy: end, now: start.addingTimeInterval(210)) == .movement)
        // one twitch is not enough
        let twitch = Self.epochs(from: start, [0.004, 0.005, 0.004, 0.005, 0.004, 0.004, 0.04])
        #expect(SmartWake.decide(twitch, windowStart: start, wakeBy: end, now: start.addingTimeInterval(210)) == nil)
    }

    @Test func smartWakeOnHeartRateAndDeadline() {
        let start = F.at(0, 7, 10), end = F.at(0, 7, 40)
        let e = Self.epochs(from: start, [0.004, 0.004, 0.004, 0.004, 0.004, 0.004], hr: [50, 51, 50, 52, 57, 58])
        #expect(SmartWake.decide(e, windowStart: start, wakeBy: end, now: start.addingTimeInterval(180)) == .heartRate)
        #expect(SmartWake.decide([], windowStart: start, wakeBy: end, now: end) == .deadline)
    }

    @Test func napCountsFromSleepOnset() {
        let start = F.at(0, 15)
        // 4 restless epochs (2 minutes), then still: onset at 2 minutes in
        let e = Self.epochs(from: start, [0.05, 0.04, 0.03, 0.05] + Array(repeating: 0.005, count: 12))
        let onset = start.addingTimeInterval(120)
        #expect(NapPlan.decide(e, start: start, napMinutes: 15, now: start.addingTimeInterval(480)) == .asleep(since: onset))
        #expect(NapPlan.decide(e, start: start, napMinutes: 15, now: onset.addingTimeInterval(15 * 60)) == .wake(.deadline))
        #expect(NapPlan.decide(Self.epochs(from: start, [0.05, 0.05]), start: start, napMinutes: 15, now: start.addingTimeInterval(60)) == .fallingAsleep)
        #expect(NapPlan.decide([], start: start, napMinutes: 15, now: start.addingTimeInterval(30 * 60)) == .wake(.deadline))   // capped
    }

    @Test func dozeNeedsStillnessAndAHeartRateDrop() {
        let start = F.at(0, 14)
        let sitting = Self.epochs(from: start, Array(repeating: 0.03, count: 20), hr: Array(repeating: 70, count: 20))
        let base = DozeDetector.baseline(sitting)
        #expect(base == 70)
        let reading = sitting + Self.epochs(from: start.addingTimeInterval(600), Array(repeating: 0.005, count: 6), hr: Array(repeating: 69, count: 6))
        #expect(!DozeDetector.isDozing(reading, baselineHR: base))          // still, but heart rate barely moved
        let nodding = sitting + Self.epochs(from: start.addingTimeInterval(600), Array(repeating: 0.005, count: 6), hr: Array(repeating: 62, count: 6))
        #expect(DozeDetector.isDozing(nodding, baselineHR: base))            // still and 11% lower
        let noHR = Self.epochs(from: start, Array(repeating: 0.005, count: 10))
        #expect(DozeDetector.isDozing(noHR, baselineHR: nil))                // 5 minutes still without heart rate
    }
}
