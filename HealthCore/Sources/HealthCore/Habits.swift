import Foundation

/// The three habits that feed recovery and that you decide each day, each with a target from the literature.
public enum HabitKind: String, CaseIterable, Sendable {
    case sleep, wake, food, training
}

public struct HabitDay: Identifiable, Sendable {
    public let date: Date
    public let score: Double?        // 0 to 100, how close the day came
    public let hit: Bool?            // target met; nil when there is no data for the day
    public var id: Date { date }
}

public struct Habit: Identifiable, Sendable {
    public let kind: HabitKind
    public let latest: HabitDay?
    /// The last 7 days, oldest first, with nil for days without data.
    public let week: [HabitDay]
    public let streak: Int
    /// 0 to 100: builds slowly with each hit and dips only a little on a miss (see `HabitEngine.strength`).
    public let strength: Double
    public var hitsThisWeek: Int { week.filter { $0.hit == true }.count }
    public var daysThisWeek: Int { week.filter { $0.hit != nil }.count }
    public var id: HabitKind { kind }
}

public enum HabitEngine {
    /// At least 7 hours: the joint consensus of the American Academy of Sleep Medicine and Sleep Research Society,
    /// Watson et al. (2015), "Recommended amount of sleep for a healthy adult", Sleep 38(6).
    public static let sleepHours = 7.0
    /// The default protein target when none is set. 1.6 g/kg is where resistance-training gains in lean mass
    /// levelled off in a meta-analysis of 49 trials, with an upper confidence bound near 2.2 (Morton et al. 2018,
    /// Br J Sports Med 52(6)). The app passes the target from Settings instead.
    public static let proteinPerKg = 1.6
    /// Calories within 10% of the goal intake. The goal itself comes from the weight goal; for lean gain about
    /// 0.25 to 0.5% of body weight per week is the recommended range (Iraki et al. 2019, "Nutrition
    /// recommendations for bodybuilders in the off-season", Sports 7(7)).
    public static let calorieTolerance = 0.10

    /// Sleep: the night's sleep score; hit at 7 hours asleep or more.
    public static func sleepDay(_ night: SleepNight, score: Double) -> HabitDay {
        HabitDay(date: night.date, score: score, hit: night.asleep / 3600 >= sleepHours)
    }

    /// Food: the balance food score with protein judged against your target; hit when protein reaches it and
    /// calories land within 10% of the goal (protein alone when there is no goal intake yet).
    public static func foodDay(_ s: HealthSnapshot, on day: Date, weightKg: Double?, goalIntake: Double?,
                               proteinTarget: Double = proteinPerKg) -> HabitDay? {
        guard let intake = s.dietaryEnergy.value(on: day), intake > NutritionEngine.loggedMinimum else { return nil }
        let protein = s.protein.value(on: day)
        let score = BalanceEngine.food(intake: intake, protein: protein, weightKg: weightKg, goalIntake: goalIntake,
                                       proteinTarget: proteinTarget,
                                       quality: DietQualityEngine.score(s, on: day, proteinTarget: weightKg.map { $0 * proteinTarget })?.score)
        var hit: Bool?
        if let p = protein, let w = weightKg, w > 0 {
            let caloriesOK = goalIntake.map { abs(intake - $0) / $0 <= calorieTolerance } ?? true
            hit = p / w >= proteinTarget && caloriesOK
        }
        return HabitDay(date: day, score: score, hit: hit)
    }

    /// Training: strain against the day's recovery-based target (`BalanceEngine.strain`); hit when on target,
    /// which includes rest days.
    public static func trainingDay(strain: Double, target: ClosedRange<Double>, trained: Bool, on day: Date) -> HabitDay {
        let score = BalanceEngine.strain(strain, target: target, trained: trained)
        return HabitDay(date: day, score: score, hit: score >= 100)
    }

    /// Consecutive hits counting back from the most recent day with data.
    public static func streak(_ days: [HabitDay]) -> Int {
        var n = 0
        for d in days.reversed() where d.hit != nil {
            if d.hit == true { n += 1 } else { break }
        }
        return n
    }

    /// Habit strength: each day with data moves it 1/30 of the way to 100 on a hit or 0 on a miss. Habits took a
    /// median of 66 days to become automatic and a single missed day did not set people back (Lally et al. 2010,
    /// "How are habits formed: modelling habit formation in the real world", Eur J Soc Psychol 40(6)); a slow
    /// average reflects both: weeks to build, one miss costs little. The 30-day constant is a design choice.
    public static func strength(_ days: [HabitDay]) -> Double {
        var s = 0.0
        for d in days { if let h = d.hit { s += ((h ? 100 : 0) - s) / 30 } }
        return s
    }

    /// All three habits over the last `history` days. Sleep is keyed by the morning (the night just slept); food
    /// and training by the day itself, up to yesterday, the last complete day.
    public static func evaluate(_ s: HealthSnapshot, day: Date, sleepScore: (SleepNight) -> Double, training: TrainingResult?,
                                recovery: [DailyValue], weightKg: Double?, goalIntake: Double?,
                                proteinTarget: Double = proteinPerKg, wakeGoal: Double? = nil, history: Int = 90) -> [Habit] {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -history, to: day)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)!

        let sleepDays = s.sleep.filter { $0.date > since && $0.date <= day }.map { sleepDay($0, score: sleepScore($0)) }
        var foodDays: [HabitDay] = [], trainingDays: [HabitDay] = []
        for back in (1...history).reversed() {
            let d = cal.date(byAdding: .day, value: -back, to: day)!
            foodDays.append(foodDay(s, on: d, weightKg: weightKg, goalIntake: goalIntake, proteinTarget: proteinTarget)
                            ?? HabitDay(date: d, score: nil, hit: nil))
            if let st = training?.days.first(where: { cal.isDate($0.date, inSameDayAs: d) })?.strain, let r = recovery.value(on: d) {
                let trained = s.workouts.contains { cal.isDate($0.start, inSameDayAs: d) }
                trainingDays.append(trainingDay(strain: st, target: BalanceEngine.target(recovery: r), trained: trained, on: d))
            } else {
                trainingDays.append(HabitDay(date: d, score: nil, hit: nil))
            }
        }

        func habit(_ kind: HabitKind, _ days: [HabitDay], weekEnd: Date) -> Habit {
            let byDay = Dictionary(days.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
            let week = (0..<7).reversed().map { back -> HabitDay in
                let d = cal.date(byAdding: .day, value: -back, to: weekEnd)!
                return byDay[d] ?? HabitDay(date: d, score: nil, hit: nil)
            }
            return Habit(kind: kind, latest: days.last { $0.hit != nil || $0.score != nil }, week: week,
                         streak: streak(days), strength: strength(days))
        }
        var habits = [habit(.sleep, sleepDays, weekEnd: day)]
        if let goal = wakeGoal {
            // Wake on time: within 30 minutes of the goal (`SleepPlan.onTimeMinutes`), keyed by the morning
            let wakeDays = s.sleep.filter { $0.date > since && $0.date <= day }.map { n -> HabitDay in
                let dev = SleepPlan.wakeDeviation(n, goal: goal)
                return HabitDay(date: n.date, score: SleepPlan.wakeScore(deviation: dev), hit: abs(dev) <= SleepPlan.onTimeMinutes)
            }
            habits.append(habit(.wake, wakeDays, weekEnd: day))
        }
        return habits + [habit(.food, foodDays, weekEnd: yesterday), habit(.training, trainingDays, weekEnd: yesterday)]
    }
}
