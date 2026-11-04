import Foundation

// All functions in HealthCore are pure: snapshot in, results out.

public enum Stats {
    public static func mean(_ x: [Double]) -> Double? {
        x.isEmpty ? nil : x.reduce(0, +) / Double(x.count)
    }

    /// Sample standard deviation with Bessel's correction (divides by n - 1).
    public static func sd(_ x: [Double]) -> Double? {
        guard x.count > 1, let m = mean(x) else { return nil }
        return sqrt(x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1))
    }

    /// Linear interpolation between order statistics, `p` in 0...1.
    /// Hyndman and Fan (1996), "Sample quantiles in statistical packages", definition 7.
    /// Same as numpy.percentile and R's default quantile type.
    public static func percentile(_ x: [Double], _ p: Double) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        let idx = p * Double(s.count - 1)
        let lo = Int(idx.rounded(.down)), hi = Int(idx.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (idx - Double(lo))
    }

    /// Standard normal CDF via the identity Φ(z) = (1 + erf(z / √2)) / 2.
    /// Abramowitz and Stegun (1964), Handbook of Mathematical Functions, chapter 26.
    public static func normalCDF(_ z: Double) -> Double {
        0.5 * (1 + erf(z / 2.0.squareRoot()))
    }

    /// Ordinary least squares slope in units per day: Σ(x - x̄)(y - ȳ) / Σ(x - x̄)².
    public static func slopePerDay(_ pts: [DailyValue]) -> Double? {
        guard pts.count >= 3, let t0 = pts.first?.date else { return nil }
        let xs = pts.map { $0.date.timeIntervalSince(t0) / 86_400 }
        let ys = pts.map(\.value)
        guard let mx = mean(xs), let my = mean(ys) else { return nil }
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        return den > 0 ? num / den : nil
    }

    /// Pearson correlation coefficient.
    public static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 2, let mx = mean(x), let my = mean(y) else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        return sxx > 0 && syy > 0 ? sxy / (sxx * syy).squareRoot() : nil
    }

    /// Lag-1 autocorrelation, Σ(x_t − x̄)(x_(t+1) − x̄) / Σ(x_t − x̄)².
    public static func autocorrelation1(_ x: [Double]) -> Double? {
        guard x.count > 2, let m = mean(x) else { return nil }
        let den = x.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        guard den > 0 else { return nil }
        return zip(x, x.dropFirst()).reduce(0) { $0 + ($1.0 - m) * ($1.1 - m) } / den
    }

    /// Residuals of y after OLS on an intercept plus the given columns, solved by the normal equations with
    /// Gaussian elimination. Columns that are constant (a weekday that never occurs) are dropped first.
    /// By the Frisch-Waugh-Lovell theorem (Frisch and Waugh 1933, Econometrica 1(4)), correlating the residuals
    /// of x and y gives their partial correlation with those columns held fixed.
    public static func residuals(_ y: [Double], controls: [[Double]]) -> [Double]? {
        let n = y.count
        let cols = [[Double](repeating: 1, count: n)] + controls.filter { c in
            c.count == n && (c.max() ?? 0) - (c.min() ?? 0) > 1e-12
        }
        let k = cols.count
        guard n > k else { return nil }
        // Augmented normal equations [X'X | X'y]
        var a = (0..<k).map { i in
            (0..<k).map { j in zip(cols[i], cols[j]).reduce(0) { $0 + $1.0 * $1.1 } } + [zip(cols[i], y).reduce(0) { $0 + $1.0 * $1.1 }]
        }
        for c in 0..<k {
            guard let p = (c..<k).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[p][c]) > 1e-9 else { return nil }
            a.swapAt(c, p)
            for r in 0..<k where r != c {
                let f = a[r][c] / a[c][c]
                for j in c...k { a[r][j] -= f * a[c][j] }
            }
        }
        let beta = (0..<k).map { a[$0][k] / a[$0][$0] }
        return (0..<n).map { i in y[i] - (0..<k).reduce(0) { $0 + beta[$1] * cols[$1][i] } }
    }

    /// Benjamini-Hochberg adjusted p-values (q-values) controlling the false discovery rate.
    /// Benjamini and Hochberg (1995), "Controlling the false discovery rate", J R Stat Soc B 57(1).
    public static func benjaminiHochberg(_ p: [Double]) -> [Double] {
        let m = Double(p.count)
        let order = p.indices.sorted { p[$0] < p[$1] }
        var q = [Double](repeating: 1, count: p.count)
        var running = 1.0
        for (rank, i) in order.enumerated().reversed() {
            running = min(running, p[i] * m / Double(rank + 1))
            q[i] = min(1, running)
        }
        return q
    }

    /// Ranks with ties given their average rank, 1-based.
    public static func ranks(_ x: [Double]) -> [Double] {
        let order = x.indices.sorted { x[$0] < x[$1] }
        var r = [Double](repeating: 0, count: x.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count && x[order[j + 1]] == x[order[i]] { j += 1 }
            let avg = Double(i + j) / 2 + 1
            for k in i...j { r[order[k]] = avg }
            i = j + 1
        }
        return r
    }

    /// Spearman rank correlation: Pearson on average ranks, so it handles ordinal ratings with many ties.
    public static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count else { return nil }
        return pearson(ranks(x), ranks(y))
    }
}
