import Foundation

/// Small seeded generator, so mock data and Monte Carlo bands are identical on every run.
/// SplitMix64: Steele, Lea and Flood (2014), "Fast splittable pseudorandom number generators", OOPSLA.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func uniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Standard normal via Box-Muller: Box and Muller (1958), Ann. Math. Statist. 29(2):610-611.
    mutating func normal() -> Double {
        let u1 = max(uniform(), .leastNonzeroMagnitude)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * uniform())
    }

    mutating func uuid() -> UUID {
        let a = next(), b = next()
        return UUID(uuid: (UInt8(truncatingIfNeeded: a), UInt8(truncatingIfNeeded: a >> 8), UInt8(truncatingIfNeeded: a >> 16),
                           UInt8(truncatingIfNeeded: a >> 24), UInt8(truncatingIfNeeded: a >> 32), UInt8(truncatingIfNeeded: a >> 40),
                           UInt8(truncatingIfNeeded: a >> 48), UInt8(truncatingIfNeeded: a >> 56), UInt8(truncatingIfNeeded: b),
                           UInt8(truncatingIfNeeded: b >> 8), UInt8(truncatingIfNeeded: b >> 16), UInt8(truncatingIfNeeded: b >> 24),
                           UInt8(truncatingIfNeeded: b >> 32), UInt8(truncatingIfNeeded: b >> 40), UInt8(truncatingIfNeeded: b >> 48),
                           UInt8(truncatingIfNeeded: b >> 56)))
    }
}
