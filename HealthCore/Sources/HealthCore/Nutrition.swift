import Foundation

public struct NutritionResult: Sendable {
    public let daysLogged: Int
    public let avgIntake: Double?
    /// Adaptive TDEE when there is enough data, otherwise the watch's basal plus active energy.
    public let avgExpenditure: Double?
    public let expenditureIsAdaptive: Bool
    public let balance: Double?
    public let avgProtein: Double?
    public let proteinPerKg: Double?
    public var avgFat: Double? = nil
    public var avgCarbs: Double? = nil
    public var avgSugar: Double? = nil
    public var avgFiber: Double? = nil
    public var tdee: TDEEEstimate? = nil
    public var meals: MealTiming? = nil

    public init(daysLogged: Int, avgIntake: Double?, avgExpenditure: Double?, expenditureIsAdaptive: Bool = false,
                balance: Double?, avgProtein: Double?, proteinPerKg: Double?) {
        self.daysLogged = daysLogged
        self.avgIntake = avgIntake
        self.avgExpenditure = avgExpenditure
        self.expenditureIsAdaptive = expenditureIsAdaptive
        self.balance = balance
        self.avgProtein = avgProtein
        self.proteinPerKg = proteinPerKg
    }

    /// Daily intake that would move the trend weight at `kgPerWeek`, from the adaptive TDEE.
    public func suggestedIntake(kgPerWeek: Double) -> Double? {
        tdee.map { $0.kcal + kgPerWeek * NutritionEngine.kcalPerKg / 7 }
    }
}

public struct TDEEEstimate: Sendable {
    public let kcal: Double
    public let intake: Double          // mean over logged days in the window
    public let trendPerWeek: Double    // kg
    public let loggedDays: Int
    public let windowDays: Int
}

public struct Meal: Sendable, Equatable {
    public let start: Date
    public let end: Date               // time of the last item in the meal
    public let kcal: Double
}

public struct MealTiming: Sendable {
    /// Average clock time of the last meal before sleep, minutes after the midnight before it: 1140 is 19:00,
    /// 1470 is 00:30 the next day. Averages cleanly across midnight.
    public let lastMealMinutes: Double
    /// Mean gap from the last meal to falling asleep, hours.
    public let gapHours: Double
    public let lateNights: Int         // last meal under 3 h before sleep
    public let nights: Int
    public let mealsPerDay: Double
    /// The food app writes hourly totals (Cronometer does), so times are only good to about half an hour.
    public var hourly = false
}

public struct LastMeal: Identifiable, Sendable {
    public let night: Date             // the morning the night ends
    public let time: Date
    public let gapHours: Double        // to falling asleep
    public var id: Date { night }
}

/// One logged day, for the nutrition overview.
public struct NutritionDay: Identifiable, Sendable {
    public let date: Date
    public let kcal: Double
    public let protein: Double?
    public let fat: Double?
    public let carbs: Double?
    public let fiber: Double?
    public let sugar: Double?
    public var id: Date { date }
}

public enum NutritionEngine {
    /// Energy content of body weight change. Wishnofsky (1958), "Caloric equivalents of gained or lost weight",
    /// Am J Clin Nutr 6(5): 3500 kcal per lb, about 7700 kcal per kg. An approximation: Hall (2008, Int J Obes 32(3))
    /// shows the real figure depends on how much of the change is fat versus lean tissue. Lean gain stores less
    /// energy per kg, so during a lean bulk this overstates the surplus needed. Shown as an estimate.
    public static let kcalPerKg = 7700.0
    /// A day counts as logged above this many kcal; less is a forgotten or partial log.
    static let loggedMinimum = 300.0
    static let tdeeWindow = 28

    /// Last 7 complete days.
    public static func evaluate(_ s: HealthSnapshot, day: Date) -> NutritionResult {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let logged = s.dietaryEnergy.recent(days: 7, from: yesterday).filter { $0.value > loggedMinimum }
        let days = logged.map(\.date)
        let intake = Stats.mean(logged.map(\.value))
        let watch = Stats.mean(days.compactMap { d -> Double? in
            guard let b = s.basalEnergy.value(on: d) else { return nil }
            return b + (s.activeEnergy.value(on: d) ?? 0)
        })
        let tdee = tdee(s, endingOn: yesterday)
        let expenditure = tdee?.kcal ?? watch
        func avg(_ series: [DailyValue]) -> Double? { Stats.mean(days.compactMap { series.value(on: $0) }) }
        let protein = avg(s.protein)
        let weight = s.weight.last?.value
        var r = NutritionResult(
            daysLogged: logged.count,
            avgIntake: intake,
            avgExpenditure: expenditure,
            expenditureIsAdaptive: tdee != nil,
            balance: intake.flatMap { i in expenditure.map { i - $0 } },
            avgProtein: protein,
            proteinPerKg: protein.flatMap { p in weight.map { p / $0 } }
        )
        r.avgFat = avg(s.fat)
        r.avgCarbs = avg(s.carbs)
        r.avgSugar = avg(s.sugar)
        r.avgFiber = avg(s.fiber)
        r.tdee = tdee
        let since = Calendar.current.date(byAdding: .day, value: -14, to: day)!
        r.meals = mealTiming(meals(s.foodLog), nights: s.sleep.filter { $0.date > since })
        r.meals?.hourly = isHourly(s.foodLog)
        return r
    }

    /// Adaptive TDEE, the MacroFactor idea: what you ate minus what went into (or came out of) body weight.
    /// TDEE = mean intake − slope of trend weight (kg/day) · 7700, over the last 28 days. The trend is
    /// `BodyEngine.ema`, so day-to-day water swings don't count as tissue. Needs 14 logged days and 8 weigh-ins
    /// in the window, and assumes the unlogged days look like the logged ones.
    public static func tdee(_ s: HealthSnapshot, endingOn day: Date) -> TDEEEstimate? {
        let logged = s.dietaryEnergy.recent(days: tdeeWindow, from: day).filter { $0.value > loggedMinimum }
        let trend = BodyEngine.ema(s.weight).recent(days: tdeeWindow, from: day)
        guard logged.count >= 14, trend.count >= 8,
              let intake = Stats.mean(logged.map(\.value)), let slope = Stats.slopePerDay(trend) else { return nil }
        return TDEEEstimate(kcal: intake - slope * kcalPerKg, intake: intake, trendPerWeek: slope * 7,
                            loggedDays: logged.count, windowDays: tdeeWindow)
    }

    /// One TDEE estimate per day over the last `days`, for the trend chart.
    public static func tdeeHistory(_ s: HealthSnapshot, days: Int, endingOn day: Date) -> [DailyValue] {
        let cal = Calendar.current
        return (0..<days).reversed().compactMap { back in
            let d = cal.date(byAdding: .day, value: -back, to: day)!
            return tdee(s, endingOn: d).map { DailyValue(date: d, value: $0.kcal) }
        }
    }

    /// Food samples become meals: items logged within 45 minutes of the previous one join it. Most food apps write
    /// one sample per item or per meal at the time eaten. Cronometer writes hourly totals stamped on the hour; then
    /// each sample is placed mid-hour (the expected time of food eaten somewhere in that hour) and neighbouring
    /// hours join, so a meal from 12:50 to 13:10 stays one meal.
    public static func meals(_ food: [Reading], gap: TimeInterval = 45 * 60) -> [Meal] {
        let hourly = isHourly(food)
        let join = hourly ? 3600 : gap
        var out: [Meal] = []
        for item in food.sorted(by: { $0.date < $1.date }) where item.value > 0 {
            let r = hourly ? Reading(date: item.date.addingTimeInterval(1800), value: item.value) : item
            if let last = out.last, r.date.timeIntervalSince(last.end) <= join {
                out[out.count - 1] = Meal(start: last.start, end: r.date, kcal: last.kcal + r.value)
            } else {
                out.append(Meal(start: r.date, end: r.date, kcal: r.value))
            }
        }
        return out
    }

    /// True when every food sample sits exactly on the hour, which only happens with hourly totals.
    public static func isHourly(_ food: [Reading]) -> Bool {
        let cal = Calendar.current
        let items = food.filter { $0.value > 0 }
        return items.count >= 5 && items.allSatisfy {
            let c = cal.dateComponents([.minute, .second], from: $0.date)
            return c.minute == 0 && c.second == 0
        }
    }

    /// Logged days (over 300 kcal) in the last `days` ending on `day`, oldest first.
    public static func daily(_ s: HealthSnapshot, days: Int, endingOn day: Date) -> [NutritionDay] {
        s.dietaryEnergy.recent(days: days, from: day).filter { $0.value > loggedMinimum }.map { d in
            NutritionDay(date: d.date, kcal: d.value, protein: s.protein.value(on: d.date), fat: s.fat.value(on: d.date),
                         carbs: s.carbs.value(on: d.date), fiber: s.fiber.value(on: d.date), sugar: s.sugar.value(on: d.date))
        }
    }

    /// Last meal before each night's sleep, within 12 hours of it. Eating close to bedtime has been linked to
    /// worse sleep (Crispim et al. 2011, "Relationship between food intake and sleep pattern in healthy
    /// individuals", J Clin Sleep Med 7(6)); 3 hours is a common rule of thumb, not a proven threshold.
    /// Phase 5 checks whether it matters for you.
    public static func mealTiming(_ meals: [Meal], nights: [SleepNight]) -> MealTiming? {
        let cal = Calendar.current
        let last = lastMeals(meals, nights: nights)
        // Clock time relative to the midnight before the night's date (the morning), so 19:30 is 1170, 00:30 is 1470.
        let clock = last.map { $0.time.timeIntervalSince(cal.startOfDay(for: $0.night)) / 60 + 1440 }
        guard let c = Stats.mean(clock), let g = Stats.mean(last.map(\.gapHours)) else { return nil }
        let first = meals.first.map { cal.startOfDay(for: $0.start) }, end = meals.last.map { cal.startOfDay(for: $0.start) }
        let span = first.flatMap { f in end.map { (cal.dateComponents([.day], from: f, to: $0).day ?? 0) + 1 } } ?? 1
        return MealTiming(lastMealMinutes: c, gapHours: g, lateNights: last.filter { $0.gapHours < 3 }.count,
                          nights: last.count, mealsPerDay: Double(meals.count) / Double(span))
    }

    /// The last meal within 12 hours before each night's sleep, nights without one left out.
    public static func lastMeals(_ meals: [Meal], nights: [SleepNight]) -> [LastMeal] {
        nights.compactMap { n in
            meals.last { $0.end <= n.start && n.start.timeIntervalSince($0.end) <= 12 * 3600 }
                .map { LastMeal(night: n.date, time: $0.end, gapHours: n.start.timeIntervalSince($0.end) / 3600) }
        }
    }
}
