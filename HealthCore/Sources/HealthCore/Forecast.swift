import Foundation

/// Posterior of a Bayesian linear regression: θ ~ N(mean, cov), noise variance σ².
public struct Posterior: Sendable {
    public let mean: [Double]
    public let cov: [[Double]]
    public let sigma2: Double
    public let n: Int
}

public enum BayesianRegression {
    /// Conjugate Normal prior θ ~ N(m₀, S₀) with S₀ diagonal, and Gaussian noise of known variance σ².
    /// The posterior is Normal again (Bishop 2006, Pattern Recognition and Machine Learning, section 3.3,
    /// eq. 3.50 and 3.51):
    ///     S_N⁻¹ = S₀⁻¹ + XᵀX / σ²
    ///     m_N   = S_N (S₀⁻¹ m₀ + Xᵀy / σ²)
    /// With little data m_N stays near the prior; with lots it moves to least squares. The prior is ridge
    /// regression in disguise: a penalty pulling each coefficient toward its prior mean.
    public static func posterior(_ x: [[Double]], _ y: [Double], priorMean m0: [Double], priorSD s0: [Double],
                                 sigma2: Double) -> Posterior? {
        let k = m0.count
        guard sigma2 > 0, x.count == y.count, x.allSatisfy({ $0.count == k }) else { return nil }
        var precision = (0..<k).map { i in (0..<k).map { j in i == j ? 1 / (s0[i] * s0[i]) : 0 } }
        var rhs = (0..<k).map { m0[$0] / (s0[$0] * s0[$0]) }
        for (row, t) in zip(x, y) {
            for i in 0..<k {
                rhs[i] += row[i] * t / sigma2
                for j in 0..<k { precision[i][j] += row[i] * row[j] / sigma2 }
            }
        }
        guard let cov = Matrix.inverse(precision) else { return nil }
        let mean = (0..<k).map { i in (0..<k).reduce(0) { $0 + cov[i][$1] * rhs[$1] } }
        return Posterior(mean: mean, cov: cov, sigma2: sigma2, n: y.count)
    }

    /// σ² is unknown, so it is estimated from the data (empirical Bayes plug-in): start from the variance of y,
    /// fit, re-estimate σ² as RSS / (n − k) at the posterior mean, and fit once more.
    public static func fit(_ x: [[Double]], _ y: [Double], priorMean: [Double], priorSD: [Double]) -> Posterior? {
        guard y.count > priorMean.count + 2, let v = Stats.sd(y).map({ $0 * $0 }), v > 0,
              let first = posterior(x, y, priorMean: priorMean, priorSD: priorSD, sigma2: v) else { return nil }
        let rss = zip(x, y).reduce(0.0) { acc, p in
            let e = p.1 - zip(p.0, first.mean).reduce(0) { $0 + $1.0 * $1.1 }
            return acc + e * e
        }
        return posterior(x, y, priorMean: priorMean, priorSD: priorSD, sigma2: max(rss / Double(y.count - priorMean.count), 1e-9))
    }
}

enum Matrix {
    /// Gauss-Jordan elimination with partial pivoting. Fine for the 9 × 9 systems here.
    static func inverse(_ m: [[Double]]) -> [[Double]]? {
        let n = m.count
        var a = m.enumerated().map { i, row in row + (0..<n).map { $0 == i ? 1.0 : 0 } }
        for c in 0..<n {
            guard let p = (c..<n).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[p][c]) > 1e-12 else { return nil }
            a.swapAt(c, p)
            let d = a[c][c]
            for j in 0..<(2 * n) { a[c][j] /= d }
            for r in 0..<n where r != c {
                let f = a[r][c]
                if f != 0 { for j in 0..<(2 * n) { a[r][j] -= f * a[c][j] } }
            }
        }
        return a.map { Array($0[n...]) }
    }

    /// Lower triangular L with L·Lᵀ = m, for drawing correlated samples.
    static func cholesky(_ m: [[Double]]) -> [[Double]]? {
        let n = m.count
        var l = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0...i {
                let s = (0..<j).reduce(m[i][j]) { $0 - l[i][$1] * l[j][$1] }
                if i == j {
                    guard s > 0 else { return nil }
                    l[i][i] = s.squareRoot()
                } else {
                    l[i][j] = s / l[j][j]
                }
            }
        }
        return l
    }
}

public struct CurvePoint: Identifiable, Sendable {
    public let day: Int        // mornings after the session, 1 = next morning
    public let mean: Double
    public let low: Double     // 10th percentile of the posterior
    public let high: Double    // 90th percentile
    public var id: Int { day }
}

public struct HorizonSkill: Identifiable, Sendable {
    public let horizon: Int
    public let modelMAE: Double
    public let naiveMAE: Double
    public let rmse: Double
    public let n: Int
    /// 1 − model error / naive error: above 0 means the model beats "same as today".
    public var skill: Double { naiveMAE > 0 ? 1 - modelMAE / naiveMAE : 0 }
    public var id: Int { horizon }
}

public struct ForecastDay: Identifiable, Sendable {
    public let date: Date
    public let planned: Double
    public let rest: Double
    public let band: Double           // ± from the backtest error at this horizon, about 80%
    public let strengthPlanned: Bool
    public var id: Date { date }
}

/// One outcome series (recovery or HRV) modelled as
///     y_M − μ = φ·(y_(M−1) − μ) + Σ_k β_k·strength(M − k) + Σ_k γ_k·other(M − k) + ε,   k = 1…4
/// μ is your average, φ how much of yesterday's deviation carries over, and β_k, γ_k how a workout k days ago
/// shifts the morning. strength(d) is 1 when a strength workout started on day d.
public struct ReadinessModel: Sendable {
    public let name: String
    public let mu: Double
    public let posterior: Posterior
    public var phi: Double { posterior.mean[0] }
    public var strength: [Double] { Array(posterior.mean[1...ReadinessEngine.lags]) }
    public var other: [Double] { Array(posterior.mean[(ReadinessEngine.lags + 1)...]) }
}

public struct ReadinessForecast: Sendable {
    public let model: ReadinessModel
    public let skill: [HorizonSkill]
    /// Only horizons where the model beat the naive forecast in the backtest.
    public let days: [ForecastDay]
    public let strengthCurve: [CurvePoint]
    public let otherCurve: [CurvePoint]
}

public enum ReadinessEngine {
    public static let lags = 4
    static let minTrainingRows = 45

    /// Priors, design choices and deliberately weak: persistence φ ~ N(0.5, 0.25²) (mornings partly carry
    /// over), and a workout k days ago ~ N(0, (effectSD / 2^(k−1))²): centered on "no effect", so the data has to
    /// show one, and fading with time. The fading matters for a strict every-other-day rhythm, where a session
    /// 1 day ago always coincides with one 3 days ago: the data alone can't split the two, the prior gives it
    /// to the nearer day.
    static func prior(effectSD: Double) -> (mean: [Double], sd: [Double]) {
        let fade = (0..<lags).map { effectSD / pow(2, Double($0)) }
        return ([0.5] + [Double](repeating: 0, count: 2 * lags), [0.25] + fade + fade)
    }

    /// Workout days as sets of day starts.
    static func workoutDays(_ w: [WorkoutSummary]) -> (strength: Set<Date>, other: Set<Date>) {
        let cal = Calendar.current
        return (Set(w.filter(\.isStrength).map { cal.startOfDay(for: $0.start) }),
                Set(w.filter { !$0.isStrength }.map { cal.startOfDay(for: $0.start) }))
    }

    static func regressors(morning m: Date, previous: Double, mu: Double, strength: Set<Date>, other: Set<Date>) -> [Double] {
        let cal = Calendar.current
        let back = (1...lags).map { cal.date(byAdding: .day, value: -$0, to: m)! }
        return [previous - mu] + back.map { strength.contains($0) ? 1 : 0 } + back.map { other.contains($0) ? 1 : 0 }
    }

    /// Fits on mornings up to `through` (all when nil).
    public static func fit(_ outcome: [DailyValue], workouts: [WorkoutSummary], name: String, effectSD: Double,
                           through: Date? = nil) -> ReadinessModel? {
        let cal = Calendar.current
        let byDay = Dictionary(outcome.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        let mornings = byDay.keys.filter { through == nil || $0 <= through! }.sorted()
        guard let mu = Stats.mean(mornings.map { byDay[$0]! }) else { return nil }
        let (s, o) = workoutDays(workouts)
        var x: [[Double]] = [], y: [Double] = []
        for m in mornings {
            guard let prev = byDay[cal.date(byAdding: .day, value: -1, to: m)!] else { continue }
            x.append(regressors(morning: m, previous: prev, mu: mu, strength: s, other: o))
            y.append(byDay[m]! - mu)
        }
        guard y.count >= minTrainingRows else { return nil }
        let p = prior(effectSD: effectSD)
        return BayesianRegression.fit(x, y, priorMean: p.mean, priorSD: p.sd).map { ReadinessModel(name: name, mu: mu, posterior: $0) }
    }

    /// Runs the model forward from morning `origin` with value `start`. Workouts on days before the origin come from
    /// `past`; from the origin day on, from `future`.
    public static func project(_ m: ReadinessModel, origin: Date, start: Double, horizon: Int,
                               past: (strength: Set<Date>, other: Set<Date>),
                               future: (strength: Set<Date>, other: Set<Date>)) -> [Double] {
        let cal = Calendar.current
        let s = past.strength.filter { $0 < origin }.union(future.strength.filter { $0 >= origin })
        let o = past.other.filter { $0 < origin }.union(future.other.filter { $0 >= origin })
        var value = start, out: [Double] = []
        for h in 1...horizon {
            let morning = cal.date(byAdding: .day, value: h, to: origin)!
            let x = regressors(morning: morning, previous: value, mu: m.mu, strength: s, other: o)
            value = m.mu + zip(x, m.posterior.mean).reduce(0) { $0 + $1.0 * $1.1 }
            out.append(value)
        }
        return out
    }

    /// Rolling-origin backtest over the last `origins` mornings: refit on everything up to each origin, forecast
    /// 1 to `horizon` mornings ahead with the workouts that actually happened, and compare with the naive forecast
    /// "same as this morning".
    public static func backtest(_ outcome: [DailyValue], workouts: [WorkoutSummary], effectSD: Double,
                                origins: Int = 30, horizon: Int = 5) -> [HorizonSkill] {
        let cal = Calendar.current
        let byDay = Dictionary(outcome.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        let days = byDay.keys.sorted()
        let actual = workoutDays(workouts)
        var errors = [[(model: Double, naive: Double)]](repeating: [], count: horizon)
        for origin in days.suffix(origins + horizon).dropLast(1) {
            guard let m = fit(outcome, workouts: workouts, name: "", effectSD: effectSD, through: origin) else { continue }
            let path = project(m, origin: origin, start: byDay[origin]!, horizon: horizon, past: actual, future: actual)
            for h in 1...horizon {
                guard let truth = byDay[cal.date(byAdding: .day, value: h, to: origin)!] else { continue }
                errors[h - 1].append((abs(path[h - 1] - truth), abs(byDay[origin]! - truth)))
            }
        }
        return errors.enumerated().compactMap { i, e in
            guard e.count >= 10, let mae = Stats.mean(e.map(\.model)), let naive = Stats.mean(e.map(\.naive)) else { return nil }
            return HorizonSkill(horizon: i + 1, modelMAE: mae, naiveMAE: naive,
                                rmse: (e.reduce(0) { $0 + $1.model * $1.model } / Double(e.count)).squareRoot(), n: e.count)
        }
    }

    /// How a single session shifts the next mornings, starting from your average, with a 10 to 90% band from
    /// 400 posterior draws: d₁ = β₁, d_h = φ·d_(h−1) + β_h.
    public static func curve(_ m: ReadinessModel, strength: Bool, days: Int = 5, draws: Int = 400) -> [CurvePoint] {
        func path(_ theta: [Double]) -> [Double] {
            var d = 0.0
            return (1...days).map { h in
                let beta = h <= lags ? theta[(strength ? 0 : lags) + h] : 0
                d = theta[0] * d + beta
                return d
            }
        }
        let mean = path(m.posterior.mean)
        guard let l = Matrix.cholesky(m.posterior.cov) else {
            return mean.enumerated().map { CurvePoint(day: $0 + 1, mean: $1, low: $1, high: $1) }
        }
        var rng = SplitMix64(seed: 1)
        let k = m.posterior.mean.count
        let samples = (0..<draws).map { _ -> [Double] in
            let z = (0..<k).map { _ in rng.normal() }
            return path((0..<k).map { i in m.posterior.mean[i] + (0...i).reduce(0) { $0 + l[i][$1] * z[$1] } })
        }
        return (0..<days).map { h in
            let v = samples.map { $0[h] }
            return CurvePoint(day: h + 1, mean: mean[h], low: Stats.percentile(v, 0.1)!, high: Stats.percentile(v, 0.9)!)
        }
    }

    /// Strength days over the next `days` from your rhythm: an interval from the last session, or usual weekdays.
    public static func plannedStrength(_ load: LoadResult, from today: Date, days: Int) -> Set<Date> {
        let cal = Calendar.current
        let window = (0..<days).map { cal.date(byAdding: .day, value: $0, to: today)! }
        if let n = load.cadenceDays, let last = load.lastStrength {
            let lastDay = cal.startOfDay(for: last)
            return Set(window.filter { d in
                let gap = cal.dateComponents([.day], from: lastDay, to: d).day ?? 0
                return gap > 0 && gap % n == 0
            })
        }
        return Set(window.filter { load.typicalWeekdays.contains(cal.component(.weekday, from: $0)) })
    }

    /// Fit, backtest and forecast. Days are only kept for horizons the backtest says the model wins.
    public static func evaluate(_ outcome: [DailyValue], workouts: [WorkoutSummary], name: String, effectSD: Double,
                                plan: Set<Date>, today: Date, horizon: Int = 5) -> ReadinessForecast? {
        guard let model = fit(outcome, workouts: workouts, name: name, effectSD: effectSD),
              let last = outcome.max(by: { $0.date < $1.date }) else { return nil }
        let cal = Calendar.current
        let skill = backtest(outcome, workouts: workouts, effectSD: effectSD, horizon: horizon)
        let origin = cal.startOfDay(for: last.date)
        let actual = workoutDays(workouts)
        let todayDone = (actual.strength.filter { $0 >= origin }, actual.other.filter { $0 >= origin })
        let planned = project(model, origin: origin, start: last.value, horizon: horizon, past: actual,
                              future: (todayDone.0.union(plan), todayDone.1))
        let rest = project(model, origin: origin, start: last.value, horizon: horizon, past: actual, future: todayDone)
        let days = skill.filter { $0.skill > 0 }.map { s -> ForecastDay in
            let date = cal.date(byAdding: .day, value: s.horizon, to: origin)!
            let workoutDay = cal.date(byAdding: .day, value: -1, to: date)!
            return ForecastDay(date: date, planned: planned[s.horizon - 1], rest: rest[s.horizon - 1],
                               band: 1.2816 * s.rmse, strengthPlanned: plan.contains(workoutDay))
        }
        return ReadinessForecast(model: model, skill: skill, days: days.filter { $0.date > today || cal.isDate($0.date, inSameDayAs: today) },
                                 strengthCurve: curve(model, strength: true), otherCurve: curve(model, strength: false))
    }
}
