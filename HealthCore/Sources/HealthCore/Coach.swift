import Foundation

public struct CoachAdvice: Sendable {
    public let headline: String
    public let notes: [String]
}

public enum Coach {
    /// Rules, not a model. Every note states its reason (Omnio: explain, don't dictate).
    /// A calorie deficit is a warning because the goal is lean muscle gain.
    public static func advise(recovery: RecoveryResult, load: LoadResult, nutrition: NutritionResult,
                              proteinTarget: Double, today: Date) -> CoachAdvice {
        let headline: String
        switch recovery.zone {
        case .push?: headline = "Good day to push: go heavy or attempt a PR."
        case .moderate?: headline = "Train, but hold back. Cap effort around RPE 7 and skip the extra sets."
        case .recover?: headline = "Recovery day. Mobility, a walk, or full rest."
        case nil: headline = "Still learning your baseline. Train as planned."
        }

        var notes: [String] = []
        if let r = load.acwr {
            if r > 1.5 {
                notes.append(String(format: "Load ratio is %.2f, a big jump from your last 4 weeks. Don't add volume today.", r))
            } else if r < 0.8 {
                notes.append(String(format: "Load ratio is %.2f. You've done less than usual lately, so there's room to build.", r))
            }
        }
        if load.typicalWeekdays.contains(Calendar.current.component(.weekday, from: today)) {
            notes.append("Today is one of your usual training days.")
        }
        if let n = load.cadenceDays, let last = load.lastStrength,
           let gap = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: today).day,
           gap >= n {
            notes.append("By your usual rhythm, today is a training day.")
        }
        if let bal = nutrition.balance, bal < -300 {
            notes.append(String(format: "You've averaged %.0f kcal per day under your estimated burn this week. That can slow recovery.", -bal))
        }
        if let ppk = nutrition.proteinPerKg, ppk < proteinTarget {
            notes.append(String(format: "Protein is %.1f g/kg against your %.1f g/kg target.", ppk, proteinTarget))
        }
        return CoachAdvice(headline: headline, notes: notes)
    }
}
