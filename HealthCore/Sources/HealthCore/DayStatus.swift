import Foundation

/// A plain good, steady or take-it-easy verdict for the merged blob on Today, from the three parts it splits into.
/// Each part is graded 2 (good), 1 (fair) or 0 (poor); the day is good from an average of 1.5, steady from 0.75.
/// A poor recovery holds the day at steady at best, since it is the signal that decides training. Design choices.
public enum DayStatus: Int, Comparable, Sendable {
    case takeItEasy = 0, steady, good
    public static func < (a: DayStatus, b: DayStatus) -> Bool { a.rawValue < b.rawValue }

    /// Sleep score: 80 and up good, 60 to 80 fair (the sleep score's own bands).
    public static func sleep(_ score: Double) -> Int { score >= 80 ? 2 : (score >= 60 ? 1 : 0) }

    /// Recovery zone: push good, moderate fair, recover poor.
    public static func recovery(_ zone: Zone) -> Int { zone.rawValue }

    /// Today's strain: over the target is poor; anything up to the top of it is good, since the day isn't over.
    public static func strain(_ s: Double, target: ClosedRange<Double>) -> Int { s > target.upperBound ? 0 : 2 }

    public static func evaluate(sleepScore: Double?, zone: Zone?, strain s: Double?, target: ClosedRange<Double>?) -> DayStatus? {
        var grades: [Int] = []
        if let v = sleepScore { grades.append(sleep(v)) }
        if let z = zone { grades.append(recovery(z)) }
        if let v = s, let t = target { grades.append(strain(v, target: t)) }
        guard let mean = Stats.mean(grades.map(Double.init)) else { return nil }
        var status: DayStatus = mean >= 1.5 ? .good : (mean >= 0.75 ? .steady : .takeItEasy)
        if zone == .recover { status = min(status, .steady) }
        return status
    }
}
