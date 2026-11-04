import Foundation

public enum FeatureKind: Sendable {
    case clock       // minutes relative to midnight, negative before it: −60 is 23:00
    case kcal, grams, hours, minutes, count, strain, kg, ppm, celsius, percent, lux
    case flag        // 1 when it happened that day, 0 when not
}

/// Something that happened on a day, keyed by that day.
public struct InsightFeature: Sendable {
    public let id: String
    public let name: String
    public let kind: FeatureKind
    /// Nutrition features also control for that night's sleep, since late eating, late bedtimes and short sleep
    /// travel together.
    public let controlForSleep: Bool
    public let values: [DailyValue]
    /// A companion measure averaged in each half, so a comparison reads in context: bedtime with wake time.
    public var context: InsightContext? = nil
}

public struct InsightContext: Sendable {
    public let name: String
    public let kind: FeatureKind
    public let values: [DailyValue]
}

/// A morning outcome, keyed by the morning's date.
public struct InsightOutcome: Sendable {
    public let id: String
    public let name: String
    public let unit: String
    public let higherIsBetter: Bool
    public let values: [DailyValue]
}

public struct Insight: Identifiable, Sendable {
    public let feature: InsightFeature
    public let outcome: InsightOutcome
    /// 0 is the next morning, 1 the morning after, 2 the one after that.
    public let lag: Int
    public let n: Int
    public let effectiveN: Double
    /// Partial correlation with weekday (and sleep for nutrition) held fixed.
    public let r: Double
    public let ci: ClosedRange<Double>
    public let p: Double
    public var q: Double = 1
    /// Consecutive mornings, from `lag` on, where the effect stays significant with the same sign.
    public var mornings = 1
    /// Split at the median (or yes and no for flags): mean raw outcome in each half.
    public let threshold: Double?
    public let lowMean: Double
    public let highMean: Double
    public let lowN: Int
    public let highN: Int
    /// The feature's context measure averaged over each half, when it has one.
    public var lowContext: Double? = nil
    public var highContext: Double? = nil

    public var id: String { "\(feature.id)|\(outcome.id)|\(lag)" }
    /// Whether this relationship points the good way for the outcome.
    public var helps: Bool { (r > 0) == outcome.higherIsBetter }
}

public struct InsightReport: Sendable {
    public let findings: [Insight]   // q below the cutoff, strongest first
    public let tested: Int
    public let all: [Insight]
    public static let empty = InsightReport(findings: [], tested: 0, all: [])
}

public enum InsightsEngine {
    public static let minPairs = 30
    /// Each half of a comparison needs this many days before a pair is tested at all.
    public static let minPerBin = 15
    public static let fdr = 0.10

    /// Pairs feature day D with the outcome on morning D + 1 + lag, then tests every pair.
    /// Method, in order:
    /// 1. Deconfound: residualize both sides on weekday dummies (plus that night's sleep duration for nutrition
    ///    features) and correlate the residuals, a partial correlation by the Frisch-Waugh-Lovell theorem.
    /// 2. Autocorrelation: daily series are not independent, so n is shrunk to an effective n,
    ///    n·(1 − ρx·ρy)/(1 + ρx·ρy) with ρ the lag-1 autocorrelations: Bretherton et al. (1999), "The effective
    ///    number of spatial degrees of freedom of a time-varying field", J Climate 12(7), eq. 31.
    ///    Pairs are in date order with gaps skipped, an approximation when days are missing.
    /// 3. Confidence interval and p-value by the Fisher z-transform, atanh(r)·√(n_eff − 3) ~ N(0, 1):
    ///    Fisher (1921), "On the probable error of a coefficient of correlation", Metron 1.
    /// 4. Benjamini-Hochberg over every pair tested, keeping q < 0.10.
    public static func analyze(features: [InsightFeature], outcomes: [InsightOutcome], sleepHours: [DailyValue],
                               lags: [Int] = [0, 1, 2], skip: Set<String> = []) -> InsightReport {
        var all: [Insight] = []
        for f in features {
            for o in outcomes {
                for lag in lags where !skip.contains("\(f.id)|\(o.id)|\(lag)") {
                    if let i = test(f, o, lag: lag, sleepHours: sleepHours) { all.append(i) }
                }
            }
        }
        let q = Stats.benjaminiHochberg(all.map(\.p))
        for k in all.indices { all[k].q = q[k] }
        // One finding per feature and outcome: the earliest significant lag, plus how many mornings in a row
        // it holds with the same sign. Taking the strongest lag instead misleads with alternating habits:
        // lifting every other day makes lag 1 the mirror image of lag 0.
        let significant = Dictionary(grouping: all.filter { $0.q < fdr }) { $0.feature.id + "|" + $0.outcome.id }
        let findings = significant.values.compactMap { group -> Insight? in
            let byLag = group.sorted { $0.lag < $1.lag }
            guard var first = byLag.first else { return nil }
            var lag = first.lag
            for next in byLag.dropFirst() where next.lag == lag + 1 && (next.r > 0) == (first.r > 0) { lag = next.lag }
            first.mornings = lag - first.lag + 1
            return first
        }
        return InsightReport(findings: findings.sorted { abs($0.r) > abs($1.r) }, tested: all.count, all: all)
    }

    public static func test(_ f: InsightFeature, _ o: InsightOutcome, lag: Int, sleepHours: [DailyValue]) -> Insight? {
        let p = pairs(f, o, lag: lag, sleepHours: sleepHours)
        let cal = Calendar.current
        return correlate(x: p.map(\.x), y: p.map(\.y), weekday: p.map { cal.component(.weekday, from: $0.day) },
                         covariates: f.controlForSleep ? [p.map(\.sleep)] : [], isFlag: f.kind == .flag)
            .map { c in
                var i = Insight(feature: f, outcome: o, lag: lag, n: p.count, effectiveN: c.nEff, r: c.r, ci: c.ci, p: c.p,
                                threshold: c.threshold, lowMean: c.lowMean, highMean: c.highMean, lowN: c.lowN, highN: c.highN)
                if let ctx = f.context {
                    let byDay = Dictionary(ctx.values.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
                    let isLow = { (x: Double) in f.kind == .flag ? x < 0.5 : x < (c.threshold ?? 0) }
                    i.lowContext = Stats.mean(p.filter { isLow($0.x) }.compactMap { byDay[$0.day] })
                    i.highContext = Stats.mean(p.filter { !isLow($0.x) }.compactMap { byDay[$0.day] })
                }
                return i
            }
    }

    public struct Pair: Sendable {
        public let day: Date
        public let x: Double
        public let y: Double
        public let sleep: Double
    }

    /// Feature on day D against the outcome on morning D + 1 + lag, oldest first. Nutrition features also need
    /// the night after D, for the sleep control.
    public static func pairs(_ f: InsightFeature, _ o: InsightOutcome, lag: Int, sleepHours: [DailyValue]) -> [Pair] {
        let cal = Calendar.current
        let outcomeByDay = Dictionary(o.values.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        let sleepByDay = Dictionary(sleepHours.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        return f.values.sorted { $0.date < $1.date }.compactMap { v in
            let d = cal.startOfDay(for: v.date)
            guard let out = outcomeByDay[cal.date(byAdding: .day, value: 1 + lag, to: d)!] else { return nil }
            let sleep = sleepByDay[cal.date(byAdding: .day, value: 1, to: d)!]
            if f.controlForSleep && sleep == nil { return nil }
            return Pair(day: d, x: v.value, y: out, sleep: sleep ?? 0)
        }
    }

    struct Correlation {
        let r: Double, nEff: Double, ci: ClosedRange<Double>, p: Double
        let threshold: Double?, lowMean: Double, highMean: Double, lowN: Int, highN: Int
    }

    /// The statistics behind `test`, on aligned arrays. Weekday is 1 to 7.
    static func correlate(x: [Double], y: [Double], weekday: [Int], covariates: [[Double]], isFlag: Bool) -> Correlation? {
        let n = x.count
        guard n >= minPairs else { return nil }
        // Median split, or yes and no for flags
        let threshold = isFlag ? nil : Stats.percentile(x, 0.5)
        let low = (0..<n).filter { isFlag ? x[$0] < 0.5 : x[$0] < threshold! }
        let high = (0..<n).filter { !low.contains($0) }
        guard low.count >= minPerBin, high.count >= minPerBin,
              let lowMean = Stats.mean(low.map { y[$0] }), let highMean = Stats.mean(high.map { y[$0] }) else { return nil }

        let dummies = (2...7).map { w in weekday.map { $0 == w ? 1.0 : 0 } }
        let controls = dummies + covariates
        guard let rx = Stats.residuals(x, controls: controls), let ry = Stats.residuals(y, controls: controls),
              let r = Stats.pearson(rx, ry) else { return nil }
        let a = Stats.autocorrelation1(rx) ?? 0, b = Stats.autocorrelation1(ry) ?? 0
        let nEff = min(Double(n), max(4, Double(n) * (1 - a * b) / (1 + a * b)))
        let z = atanh(max(-0.999999, min(0.999999, r))), se = 1 / (nEff - 3).squareRoot()
        let p = 2 * (1 - Stats.normalCDF(abs(z) / se))
        return Correlation(r: r, nEff: nEff, ci: tanh(z - 1.959964 * se)...tanh(z + 1.959964 * se), p: p,
                           threshold: threshold, lowMean: lowMean, highMean: highMean, lowN: low.count, highN: high.count)
    }
}

extension InsightsEngine {
    /// The daily feature table. Each value is keyed by day D; night features describe the night after D,
    /// so they line up with the next morning's outcome.
    public static func features(_ s: HealthSnapshot, training: [TrainingDay], lifts: [LiftSession],
                                tags: [(day: Date, tags: [String])]) -> [InsightFeature] {
        let cal = Calendar.current
        let dayBefore = { (d: Date) in cal.date(byAdding: .day, value: -1, to: d)! }
        let logged = Set(s.dietaryEnergy.filter { $0.value > NutritionEngine.loggedMinimum }.map(\.date))
        let food = { (series: [DailyValue]) in series.filter { logged.contains($0.date) } }
        // Night timing, all keyed by the day before the morning and in minutes from that morning's midnight
        let bed = s.sleep.map { DailyValue(date: dayBefore($0.date), value: $0.start.timeIntervalSince(cal.startOfDay(for: $0.date)) / 60) }
        let wake = s.sleep.map { DailyValue(date: dayBefore($0.date), value: $0.end.timeIntervalSince(cal.startOfDay(for: $0.date)) / 60) }
        var out = [
            InsightFeature(id: "bedtime", name: "Bedtime", kind: .clock, controlForSleep: false, values: bed,
                           context: InsightContext(name: "waking", kind: .clock, values: wake)),
            InsightFeature(id: "wake", name: "Wake time", kind: .clock, controlForSleep: false, values: wake,
                           context: InsightContext(name: "asleep from", kind: .clock, values: bed)),
            InsightFeature(id: "midpoint", name: "Sleep midpoint", kind: .clock, controlForSleep: false,
                           values: s.sleep.map { n in
                               DailyValue(date: dayBefore(n.date),
                                          value: n.start.addingTimeInterval(n.end.timeIntervalSince(n.start) / 2).timeIntervalSince(cal.startOfDay(for: n.date)) / 60)
                           }),
            InsightFeature(id: "inBed", name: "Time in bed", kind: .hours, controlForSleep: false,
                           values: s.sleep.map { DailyValue(date: dayBefore($0.date), value: $0.end.timeIntervalSince($0.start) / 3600) }),
            InsightFeature(id: "sleep", name: "Sleep", kind: .hours, controlForSleep: false,
                           values: s.sleep.map { DailyValue(date: dayBefore($0.date), value: $0.asleep / 3600) }),
            InsightFeature(id: "intake", name: "Calories", kind: .kcal, controlForSleep: true, values: food(s.dietaryEnergy)),
            InsightFeature(id: "protein", name: "Protein", kind: .grams, controlForSleep: true, values: food(s.protein)),
            InsightFeature(id: "fat", name: "Fat", kind: .grams, controlForSleep: true, values: food(s.fat)),
            InsightFeature(id: "carbs", name: "Carbs", kind: .grams, controlForSleep: true, values: food(s.carbs)),
            InsightFeature(id: "sugar", name: "Sugar", kind: .grams, controlForSleep: true, values: food(s.sugar)),
            InsightFeature(id: "mealGap", name: "Last meal to sleep", kind: .hours, controlForSleep: true,
                           values: NutritionEngine.lastMeals(NutritionEngine.meals(s.foodLog), nights: s.sleep)
                               .map { DailyValue(date: dayBefore($0.night), value: $0.gapHours) }),
            InsightFeature(id: "steps", name: "Steps", kind: .count, controlForSleep: false, values: s.steps),
        ]
        if training.contains(where: { $0.strain != nil }) {
            out.append(InsightFeature(id: "strain", name: "Day strain", kind: .strain, controlForSleep: false,
                                      values: training.compactMap { d in d.strain.map { DailyValue(date: d.date, value: $0) } }))
        }
        // Workout days only exist from the first workout on, so rest days before it don't count as zero.
        if let first = training.first?.date {
            let byDay = Dictionary(grouping: s.workouts) { cal.startOfDay(for: $0.start) }
            let days = training.map(\.date).filter { $0 >= first }
            out.append(InsightFeature(id: "workoutMinutes", name: "Workout time", kind: .minutes, controlForSleep: false,
                                      values: days.map { d in DailyValue(date: d, value: (byDay[d] ?? []).reduce(0) { $0 + $1.duration / 60 }) }))
            out.append(InsightFeature(id: "lifted", name: "Strength workout", kind: .flag, controlForSleep: false,
                                      values: days.map { d in DailyValue(date: d, value: (byDay[d] ?? []).contains(where: \.isStrength) ? 1 : 0) }))
        }
        // Bedroom monitor: the night after day D, and the morning light on day D itself
        let room = RoomEngine.nights(s.room, sleep: s.sleep)
        let nightly = { (f: (RoomNight) -> Double?) in room.compactMap { n in f(n).map { DailyValue(date: dayBefore(n.date), value: $0) } } }
        out += [
            InsightFeature(id: "co2", name: "Bedroom CO2", kind: .ppm, controlForSleep: false, values: nightly(\.co2Mean)),
            InsightFeature(id: "roomTemp", name: "Bedroom temperature", kind: .celsius, controlForSleep: false, values: nightly(\.temperatureMean)),
            InsightFeature(id: "humidity", name: "Bedroom humidity", kind: .percent, controlForSleep: false, values: nightly(\.humidityMean)),
            InsightFeature(id: "morningLight", name: "Morning light", kind: .lux, controlForSleep: false,
                           values: RoomEngine.light(s.room, fromHour: 6, toHour: 10)),
        ]
        // Lifting days only: a heavy session against a light one, not lifting against resting.
        let volume = Dictionary(grouping: lifts) { cal.startOfDay(for: $0.start) }
            .map { DailyValue(date: $0.key, value: $0.value.reduce(0) { $0 + LiftingEngine.volumeLoad($1.sets) }) }
            .filter { $0.value > 0 }
            .sorted { $0.date < $1.date }
        out.append(InsightFeature(id: "volume", name: "Lifting volume", kind: .kg, controlForSleep: false, values: volume))
        // Tags count as "no" on untagged days between the first and last journal entry.
        let entries = Dictionary(tags.map { (cal.startOfDay(for: $0.day), $0.tags) }, uniquingKeysWith: { $0 + $1 })
        if let first = entries.keys.min(), let last = entries.keys.max() {
            let span = (0...(cal.dateComponents([.day], from: first, to: last).day ?? 0)).map { cal.date(byAdding: .day, value: $0, to: first)! }
            for tag in Set(entries.values.flatMap { $0 }).sorted() {
                out.append(InsightFeature(id: "tag:" + tag, name: tag, kind: .flag, controlForSleep: false,
                                          values: span.map { DailyValue(date: $0, value: entries[$0]?.contains(tag) == true ? 1 : 0) }))
            }
        }
        return out.filter { !$0.values.isEmpty }
    }

    public static func outcomes(_ s: HealthSnapshot, recovery: [DailyValue], feel: [DailyValue] = []) -> [InsightOutcome] {
        (feel.isEmpty ? [] : [InsightOutcome(id: "feel", name: "How you feel", unit: "of 5", higherIsBetter: true, values: feel)]) + [
            InsightOutcome(id: "recovery", name: "Recovery", unit: "", higherIsBetter: true, values: recovery),
            InsightOutcome(id: "hrv", name: "HRV", unit: "ms", higherIsBetter: true, values: s.hrv),
            InsightOutcome(id: "rhr", name: "Resting HR", unit: "bpm", higherIsBetter: false, values: s.restingHR),
            InsightOutcome(id: "efficiency", name: "Sleep efficiency", unit: "%", higherIsBetter: true,
                           values: s.sleep.compactMap { n in
                               let inBed = n.end.timeIntervalSince(n.start)
                               return inBed > 0 ? DailyValue(date: n.date, value: 100 * n.asleep / inBed) : nil
                           }),
        ]
    }

    /// Pairs that are related by definition rather than behaviour, so a "finding" would only restate arithmetic:
    /// sleep is part of the recovery score, and sleep efficiency is time asleep ÷ time in bed, so that night's
    /// bedtime, wake time, time in bed and sleep move it mechanically.
    static let mechanical: Set<String> = ["sleep|recovery|0", "bedtime|efficiency|0", "wake|efficiency|0",
                                          "inBed|efficiency|0", "sleep|efficiency|0", "midpoint|efficiency|0"]

    /// Everything in one call. Definitional pairs (`mechanical`) are skipped.
    public static func report(_ s: HealthSnapshot, recovery: [DailyValue], training: [TrainingDay], lifts: [LiftSession],
                              tags: [(day: Date, tags: [String])], feel: [DailyValue] = []) -> InsightReport {
        analyze(features: features(s, training: training, lifts: lifts, tags: tags),
                outcomes: outcomes(s, recovery: recovery, feel: feel),
                sleepHours: s.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) },
                skip: mechanical)
    }
}

public struct WeekComparison: Sendable {
    public let thisWeek: Double?
    public let usual: Double?        // the 4 weeks before
    public var change: Double? { thisWeek.flatMap { t in usual.map { t - $0 } } }
}

public enum WeeklyReport {
    /// Mean of the 7 days ending on `day` against the mean of the 28 days before them.
    public static func compare(_ values: [DailyValue], endingOn day: Date) -> WeekComparison {
        let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: day)!
        let before = Calendar.current.date(byAdding: .day, value: -1, to: weekStart)!
        return WeekComparison(thisWeek: Stats.mean(values.recent(days: 7, from: day).map(\.value)),
                              usual: Stats.mean(values.recent(days: 28, from: before).map(\.value)))
    }
}

public enum Weekly {
    /// Mean per week (Monday start, ISO 8601), dated by the week's Monday, oldest first. Weeks without data are left out.
    /// Used to keep year-long charts readable and for week-by-week comparisons.
    public static func means(_ values: [DailyValue]) -> [DailyValue] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = Calendar.current.timeZone
        return Dictionary(grouping: values) { cal.dateInterval(of: .weekOfYear, for: $0.date)!.start }
            .compactMap { week, v in Stats.mean(v.map(\.value)).map { DailyValue(date: week, value: $0) } }
            .sorted { $0.date < $1.date }
    }
}
