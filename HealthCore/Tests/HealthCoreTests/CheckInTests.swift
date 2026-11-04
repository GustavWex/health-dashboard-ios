import Foundation
import Testing
@testable import HealthCore

@Suite struct CheckInTests {
    typealias F = Fixture

    // Must match golden.py
    static let feel = (0..<20).map { Double(($0 * 7) % 5 + 1) }
    static let score = (0..<20).map { i in 40 + 4 * feel[i] + 2 * Double((i * 13) % 11) - 10 }

    @Test func spearmanWithTiesMatchesScipy() throws {
        let a = try #require(CheckInEngine.agreement(
            feel: Self.feel.enumerated().map { DailyValue(date: F.day($0.offset - 19), value: $0.element) },
            scores: Self.score.enumerated().map { DailyValue(date: F.day($0.offset - 19), value: $0.element) }))
        #expect(a.n == 20)
        #expect(close(a.rho, 0.5350428037226845))
        #expect(close(a.ci.lowerBound, 0.10735460018716889))
        #expect(close(a.ci.upperBound, 0.795633203232429))
    }

    @Test func averageRanksForTies() {
        #expect(Stats.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
    }

    @Test func needsFourteenMornings() {
        let few = (0..<13).map { DailyValue(date: F.day(-$0), value: Double($0 % 5 + 1)) }
        #expect(CheckInEngine.agreement(feel: few, scores: few) == nil)
    }

    @Test func feelBecomesAnInsightsOutcome() {
        let outcomes = InsightsEngine.outcomes(HealthSnapshot(), recovery: [], feel: [DailyValue(date: F.today, value: 4)])
        #expect(outcomes.first?.id == "feel")
        #expect(InsightsEngine.outcomes(HealthSnapshot(), recovery: []).allSatisfy { $0.id != "feel" })
    }
}
