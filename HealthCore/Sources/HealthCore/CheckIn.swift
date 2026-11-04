import Foundation

/// How well the recovery score agrees with how you say you feel: the application-grounded test of the score,
/// with you as the real user (Doshi-Velez and Kim 2017, "Towards a rigorous science of interpretable machine learning").
public struct Agreement: Sendable {
    public let n: Int
    public let rho: Double
    public let ci: ClosedRange<Double>
}

public enum CheckInEngine {
    public static let minMornings = 14

    /// Spearman's rho between the morning rating (1 to 5) and the same morning's score, with a 95% interval from
    /// the Fisher transform using the Fieller, Hartley and Pearson (1957) standard error √(1.06 / (n − 3)),
    /// "Tests for rank correlation coefficients I", Biometrika 44.
    public static func agreement(feel: [DailyValue], scores: [DailyValue]) -> Agreement? {
        let cal = Calendar.current
        let byDay = Dictionary(scores.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        let pairs = feel.compactMap { f in byDay[cal.startOfDay(for: f.date)].map { (f.value, $0) } }
        guard pairs.count >= minMornings, let rho = Stats.spearman(pairs.map(\.0), pairs.map(\.1)) else { return nil }
        let z = atanh(max(-0.999999, min(0.999999, rho))), se = (1.06 / Double(pairs.count - 3)).squareRoot()
        return Agreement(n: pairs.count, rho: rho, ci: tanh(z - 1.959964 * se)...tanh(z + 1.959964 * se))
    }
}
