import Foundation

/// How balanced the last complete day was across the three things you control: sleep, food and training load.
/// Each part is 0 to 100; the balance is their weighted mean, with missing parts' weight shared out.
/// Sleep weighs most: it acts on the same outcomes the other two aim at. Short sleep shifted weight loss from fat
/// to lean mass (Nedeltcheva et al. 2010, Ann Intern Med 153(7)), one night without sleep cut muscle protein
/// synthesis by 18% (Lamon et al. 2021, Physiol Rep 9(1)), and 5 nights of 4 h lowered it too (Saner et al. 2020,
/// J Physiol 598(8)). No study gives weights for a combined score, so 45, 30 and 25% are a judgment.
public struct BalanceScore: Sendable {
    public enum Part: String, Sendable {
        case sleep, food, strain
        public var weight: Double {
            switch self {
            case .sleep: 0.45
            case .food: 0.30
            case .strain: 0.25
            }
        }
    }
    public let score: Double
    public let parts: [(part: Part, score: Double)]

    public func score(_ p: Part) -> Double? { parts.first { $0.part == p }?.score }
}

public enum BalanceEngine {
    /// Food: diet quality 40% (`DietQualityEngine`, every nutrient against its target and limits), protein against your
    /// g/kg target 30% (full marks at the target), calories against the goal intake 30% (100 at the goal, 0 at 25%
    /// over or under). Missing parts share out their weight.
    public static func food(intake: Double?, protein: Double?, weightKg: Double?, goalIntake: Double?,
                            proteinTarget: Double, quality: Double? = nil) -> Double? {
        var parts: [(w: Double, v: Double)] = []
        if let q = quality { parts.append((0.4, q)) }
        if let p = protein, let w = weightKg, w > 0, proteinTarget > 0 {
            parts.append((0.3, 100 * min(1, (p / w) / proteinTarget)))
        }
        if let i = intake, let g = goalIntake, g > 0 {
            parts.append((0.3, 100 * max(0, 1 - abs(i - g) / (0.25 * g))))
        }
        let wsum = parts.reduce(0) { $0 + $1.w }
        return wsum > 0 ? parts.reduce(0) { $0 + $1.w * $1.v } / wsum : nil
    }

    /// Strain against the day's target band. Inside the band, or below it on a day without a workout, scores 100:
    /// rest days are part of the plan. Above the band loses 25 points per strain point; below it on a training
    /// day loses 10 per point, floored at 50, since an easy session is a smaller miss than overreaching.
    public static func strain(_ s: Double, target: ClosedRange<Double>, trained: Bool) -> Double {
        if s > target.upperBound { return max(0, 100 - 25 * (s - target.upperBound)) }
        if s < target.lowerBound && trained { return max(50, 100 - 10 * (target.lowerBound - s)) }
        return 100
    }

    /// The target band for a recovery score, the same rule as `TrainingEngine.evaluate`.
    public static func target(recovery r: Double) -> ClosedRange<Double> {
        let centre = 10.5 + 5 * (r - 50) / 50
        return max(0, centre - 2)...min(21, centre + 2)
    }

    /// Last night's sleep score, and yesterday's food and strain (the last complete day).
    public static func evaluate(_ s: HealthSnapshot, day: Date, sleepScore: Double?, training: TrainingResult?,
                                recovery: [DailyValue], weightKg: Double?, goalIntake: Double?, proteinTarget: Double) -> BalanceScore? {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)!
        var parts: [(BalanceScore.Part, Double)] = []
        if let sl = sleepScore { parts.append((.sleep, sl)) }
        let intake = s.dietaryEnergy.value(on: yesterday).flatMap { $0 > NutritionEngine.loggedMinimum ? $0 : nil }
        if intake != nil, let f = food(intake: intake, protein: s.protein.value(on: yesterday), weightKg: weightKg,
                                       goalIntake: goalIntake, proteinTarget: proteinTarget,
                                       quality: DietQualityEngine.score(s, on: yesterday, proteinTarget: weightKg.map { $0 * proteinTarget })?.score) {
            parts.append((.food, f))
        }
        if let st = training?.days.first(where: { cal.isDate($0.date, inSameDayAs: yesterday) })?.strain,
           let r = recovery.value(on: yesterday) {
            let trained = s.workouts.contains { cal.isDate($0.start, inSameDayAs: yesterday) }
            parts.append((.strain, strain(st, target: target(recovery: r), trained: trained)))
        }
        let wsum = parts.reduce(0) { $0 + $1.0.weight }
        guard wsum > 0 else { return nil }
        return BalanceScore(score: parts.reduce(0) { $0 + $1.0.weight * $1.1 } / wsum, parts: parts.map { (part: $0.0, score: $0.1) })
    }
}
