import Foundation

/// Goal arithmetic: weight for a body fat target, a height-based muscular ceiling, and what a lifting goal implies.
/// All of these are estimates and are shown as such.
public enum Goals {
    /// Weight at a target body fat with lean mass held where it is: lean / (1 − fat). Fat as a fraction.
    public static func weight(lean: Double, bodyFat: Double) -> Double? {
        guard lean > 0, bodyFat >= 0, bodyFat < 1 else { return nil }
        return lean / (1 - bodyFat)
    }

    /// Fat-free mass index, FFM / height², and the height-normalized version FFMI + 6.1·(1.8 − height).
    /// Kouri, Pope, Katz and Oliva (1995), "Fat-free mass index in users and nonusers of anabolic-androgenic
    /// steroids", Clin J Sport Med 5(4): drug-free lifters rarely exceeded a normalized FFMI of about 25.
    public static func ffmi(lean: Double, height: Double) -> (raw: Double, normalized: Double)? {
        guard lean > 0, height > 0 else { return nil }
        let raw = lean / (height * height)
        return (raw, raw + 6.1 * (1.8 - height))
    }

    public static let naturalFFMI = 25.0

    /// Lean mass at a normalized FFMI for this height: the inverse of `ffmi`.
    public static func lean(normalizedFFMI: Double, height: Double) -> Double? {
        guard height > 0 else { return nil }
        return (normalizedFFMI - 6.1 * (1.8 - height)) * height * height
    }

    /// Body weight at which a goal lift would be as strong per unit of size as your current lift. Strength grows
    /// with body mass to the power 2/3 (Jaric 2002, "Muscle strength testing: use of normalisation for body
    /// size", Sports Med 32(10)), so mass needed = mass · (goal / current)^(3/2).
    public static func weight(forLift goal: Double, current: Double, bodyWeight: Double) -> Double? {
        guard goal > 0, current > 0, bodyWeight > 0 else { return nil }
        return bodyWeight * pow(goal / current, 1.5)
    }

    /// Time to close a gap at the current rate, in the rate's time unit. nil when the rate points the other way
    /// or is effectively flat.
    public static func timeToGoal(current: Double, goal: Double, rate: Double) -> Double? {
        let gap = goal - current
        if abs(gap) < 1e-9 { return 0 }
        guard abs(rate) > 1e-6, (gap > 0) == (rate > 0) else { return nil }
        return gap / rate
    }
}
