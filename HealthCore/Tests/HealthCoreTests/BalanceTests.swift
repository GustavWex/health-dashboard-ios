import Foundation
import Testing
@testable import HealthCore

@Suite struct BalanceTests {
    typealias F = Fixture

    @Test func foodHalvesProteinAndCalories() {
        // 130 g at 65 kg is 2.0 g/kg against a 2.0 target: 100. 2,750 kcal against a 2,500 goal is 10% over: 60.
        #expect(close(BalanceEngine.food(intake: 2750, protein: 130, weightKg: 65, goalIntake: 2500, proteinTarget: 2), 80))
        #expect(close(BalanceEngine.food(intake: nil, protein: 97.5, weightKg: 65, goalIntake: nil, proteinTarget: 2), 75))
        #expect(BalanceEngine.food(intake: nil, protein: nil, weightKg: 65, goalIntake: 2500, proteinTarget: 2) == nil)
    }

    @Test func strainSparesRestDays() {
        let band = 8.0...12.0
        #expect(BalanceEngine.strain(10, target: band, trained: true) == 100)
        #expect(BalanceEngine.strain(2, target: band, trained: false) == 100)   // rest day
        #expect(BalanceEngine.strain(6, target: band, trained: true) == 80)     // easy session
        #expect(BalanceEngine.strain(14, target: band, trained: true) == 50)    // 2 over
        #expect(BalanceEngine.target(recovery: 50) == 8.5...12.5)
    }

    @Test func balanceAveragesWhatIsThere() {
        let s = HealthSnapshot(dietaryEnergy: F.series(-1...(-1)) { _ in 2500 }, protein: F.series(-1...(-1)) { _ in 130 })
        let b = BalanceEngine.evaluate(s, day: F.today, sleepScore: 70, training: nil, recovery: [], weightKg: 65,
                                       goalIntake: 2500, proteinTarget: 2)
        #expect(b?.parts.count == 2)              // no strain without training data
        #expect(close(b?.score, (0.45 * 70 + 0.30 * 100) / 0.75))   // sleep weighs 45%, food 30%
        #expect(b?.score(.food) == 100)
    }

    @Test func dietQualityScoresTargetsAndPenalisesLimits() throws {
        // Targets: protein 130 of 130 g (100%), fiber 14 of 28 g at 2,000 kcal (50%), vitamin C 180 of 90 mg (capped
        // at 100%), calcium 650 of 1,300 mg (50%): mean 75. Sodium 2,760 mg is 20% over its limit: 10 points off.
        let q = try #require(DietQualityEngine.score(kcal: 2000, amounts: ["Protein": 130, "Fiber": 14, "Vitamin C": 180,
                                                                           "Calcium": 650, "Sodium": 2760], proteinTarget: 130))
        #expect(close(q.encourage, 75))
        #expect(close(q.penalty, 10))
        #expect(close(q.score, 65))
        // Fiber scales with energy (14 g per 1,000 kcal); saturated fat over 10% of energy costs points
        let big = try #require(DietQualityEngine.score(kcal: 3000, amounts: ["Protein": 130, "Fiber": 21, "Vitamin C": 90,
                                                                             "Calcium": 1300, "Saturated fat": 40], proteinTarget: 130))
        #expect(close(big.encourage, (100 + 50 + 100 + 100) / 4))
        #expect(close(big.penalty, 0.5 * (100 * 40 / (3000 * 0.10 / 9) - 100)))    // 40 g against a 33.3 g limit
        // Upper intake levels: 60 mg iron is 33% over 45 mg
        let iron = try #require(DietQualityEngine.score(kcal: 2000, amounts: ["Protein": 130, "Fiber": 28, "Vitamin C": 90, "Iron": 60],
                                                        proteinTarget: 130))
        #expect(close(iron.penalty, 0.5 * (100 * 60.0 / 45 - 100)))
        #expect(DietQualityEngine.score(kcal: 2000, amounts: ["Protein": 50, "Fiber": 14], proteinTarget: 50) == nil)   // under 4 targets
    }

    @Test func foodWeighsQualityProteinAndCalories() {
        // quality 50 (40%), protein at target 100 (30%), calories at goal 100 (30%): 80
        #expect(close(BalanceEngine.food(intake: 2500, protein: 130, weightKg: 65, goalIntake: 2500, proteinTarget: 2, quality: 50), 80))
    }
}
