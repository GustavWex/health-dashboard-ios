import Testing
@testable import HealthCore

@Suite struct GoalsTests {
    @Test func weightAtBodyFat() {
        #expect(close(Goals.weight(lean: 56, bodyFat: 0.12), 63.63636363636363))   // 56 / 0.88
        #expect(Goals.weight(lean: 56, bodyFat: 1) == nil)
    }

    @Test func ffmiKouri() {
        let f = Goals.ffmi(lean: 56, height: 1.80)
        #expect(close(f?.raw, 17.28395061728395))          // 56 / 3.24
        #expect(close(f?.normalized, 17.28395061728395))   // no correction at 1.80 m
        let short = Goals.ffmi(lean: 56, height: 1.70)
        #expect(close(short?.normalized, 56 / (1.7 * 1.7) + 0.61))
        #expect(close(Goals.lean(normalizedFFMI: 25, height: 1.8), 81))   // 25 · 3.24
    }

    @Test func allometricLiftScaling() {
        // 80 kg goal from a 64 kg bench at 65 kg body weight: 65 · (1.25)^1.5
        #expect(close(Goals.weight(forLift: 80, current: 64, bodyWeight: 65), 90.84026158592896))
    }

    @Test func timeToGoalNeedsTheRightDirection() {
        #expect(close(Goals.timeToGoal(current: 65, goal: 70, rate: 0.25), 20))
        #expect(Goals.timeToGoal(current: 65, goal: 70, rate: -0.1) == nil)
        #expect(Goals.timeToGoal(current: 70, goal: 70, rate: 0) == 0)
    }
}
