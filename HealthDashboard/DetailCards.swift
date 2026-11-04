import SwiftUI
import HealthCore

// The full cards, shown on the detail pages behind Today's summary rows.

struct SleepCard: View {
    let model: DashboardModel

    var body: some View {
        Card(title: "Sleep", systemImage: "bed.double") {
            if let s = model.sleep {
                if let n = s.lastNight ?? s.latestNight {
                    let score = model.sleepScore(for: n)
                    NavigationLink {
                        SleepDetailView(model: model)
                    } label: {
                        HStack {
                            Text("Sleep score")
                            Text(fmt(score.score, 0))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(score.status.color)
                            Spacer()
                            Text("Details").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    HStack {
                        MetricTile(label: s.lastNight != nil ? "Last night" : "Night to " + n.date.formatted(.dateTime.weekday(.abbreviated).day()),
                                   value: fmt(n.asleep / 3600, 1, " h"),
                                   detail: fmt(n.efficiency * 100, 0, "% asleep in bed"))
                        MetricTile(label: "Awakenings", value: "\(n.awakenings)")
                        MetricTile(label: "Asleep",
                                   value: n.start.formatted(date: .omitted, time: .shortened),
                                   detail: "woke " + n.end.formatted(date: .omitted, time: .shortened))
                    }
                    StageBar(night: n)
                    Text("Watch sleep stages are rough estimates. Total sleep, awakenings and consistency are more reliable.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No sleep found in Apple Health. Wear your watch to bed with Sleep tracking on.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                ForEach(recentNaps) { nap in
                    Label("Nap \(dayWord(nap.date)) at \(nap.start.formatted(date: .omitted, time: .shortened)), \(Int(nap.asleep / 60)) min",
                          systemImage: "powersleep")
                        .font(.subheadline)
                }
                Divider()
                HStack {
                    MetricTile(label: "7-day average", value: fmt(s.avg7, 1, " h"))
                    MetricTile(label: "Sleep debt", value: fmt(s.debt7, 1, " h"),
                               detail: "7 days, need " + fmt(s.needHours, 1, " h"))
                    MetricTile(label: "Consistency",
                               value: s.consistencyMin.map { "±\(Int($0)) min" } ?? "--",
                               detail: "bedtime spread")
                }
            }
        }
    }

    /// Naps from the last two days.
    private var recentNaps: [Nap] {
        let since = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: .now))!
        return model.snapshot.naps.filter { $0.date >= since }
    }

    private func dayWord(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "today" }
        if cal.isDateInYesterday(day) { return "yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }
}

struct TrainingCard: View {
    let model: DashboardModel
    /// The Workouts tab lists every workout itself, so it hides the short list here.
    var showRecent = true

    var body: some View {
        Card(title: "Training", systemImage: "figure.strengthtraining.traditional") {
            if let l = model.load {
                let t = model.training
                HStack {
                    MetricTile(label: "Strain today", value: fmt(t?.today?.strain, 1),
                               detail: t?.strainTarget.map { "target " + fmt($0.lowerBound, 0) + " to " + fmt($0.upperBound, 0) }
                                   ?? (t?.tau == nil ? "needs 5 workouts with HR" : nil))
                    MetricTile(label: "Fitness", value: fmt(t?.fitness, 0), detail: "42-day load")
                    MetricTile(label: "Form", value: t?.form.map { String(format: "%+.0f", $0) } ?? "--",
                               detail: formText(t?.form))
                }
                HStack {
                    MetricTile(label: "Load vs normal", value: fmt(l.acwr, 2), detail: l.band)
                    MetricTile(label: "Strength per week", value: fmt(l.sessionsPerWeek, 1), detail: "last 8 weeks")
                }
                Text(rhythmText(l))
                    .font(.subheadline)
                if showRecent && !l.recent.isEmpty {
                    Divider()
                    ForEach(model.snapshot.workouts.prefix(5)) { w in
                        NavigationLink {
                            WorkoutDetailView(workout: w, tau: t?.tau, lift: model.lift(for: w))
                        } label: {
                            WorkoutRow(workout: w, tau: t?.tau)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Form is fitness minus fatigue: positive means fresher than your recent load, negative more tired.
    private func formText(_ form: Double?) -> String? {
        guard let f = form else { return nil }
        if f > 5 { return "fresh" }
        if f < -10 { return "carrying fatigue" }
        return "balanced"
    }

    private func rhythmText(_ l: LoadResult) -> String {
        if let n = l.cadenceDays {
            return n == 2 ? "You train every other day." : "You train about every \(n) days."
        }
        if l.typicalWeekdays.isEmpty { return "No regular training rhythm detected yet." }
        return "You actually train on " + l.typicalWeekdays
            .map { Calendar.current.weekdaySymbols[$0 - 1] }
            .joined(separator: " and ") + "."
    }
}

struct VitalsCard: View {
    let model: DashboardModel

    var body: some View {
        Card(title: "Overnight check", systemImage: "waveform.path.ecg.rectangle") {
            if let v = model.vitals, !v.checks.isEmpty {
                if v.severalUnusual {
                    Text("Several readings are unusual for you. Often it's a late night, alcohol or a hard session. If it lasts a few days, take it easy.")
                        .font(.subheadline)
                }
                ForEach(v.checks) { c in
                    HStack {
                        Text(c.name)
                        Spacer()
                        Text(vitalValue(c)).monospacedDigit()
                        Text(vitalLabel(c.status))
                            .font(.caption)
                            .foregroundStyle(c.status == .low || c.status == .high ? Zone.moderate.color : .secondary)
                            .frame(width: 92, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            } else {
                Text("No overnight readings yet. Wear your watch to bed.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private func vitalValue(_ c: VitalCheck) -> String {
        guard let v = c.value else { return "--" }
        let digits = c.unit == "bpm" || c.unit == "ms" || c.unit == "%" ? 0 : 1
        return fmt(v, digits, " " + c.unit)
    }

    private func vitalLabel(_ s: VitalStatus) -> String {
        switch s {
        case .normal: "In range"
        case .low: "Low for you"
        case .high: "High for you"
        case .learning: "Learning"
        case .noReading: "No reading"
        }
    }
}

struct BodyCard: View {
    let model: DashboardModel
    @AppStorage(AppSettings.goalWeightKey) private var goalWeight = 0.0

    var body: some View {
        Card(title: "Body", systemImage: "scalemass") {
            if let b = model.bodyComp, b.latestWeight != nil {
                HStack {
                    MetricTile(label: "Trend weight", value: fmt(b.trendWeight, 1, " kg"),
                               detail: "last weigh-in " + fmt(b.latestWeight, 1, " kg"))
                    MetricTile(label: "Rate",
                               value: b.ratePerWeek.map { String(format: "%+.2f kg/wk", $0) } ?? "--",
                               detail: "28-day trend")
                }
                if goalWeight > 0, let t = b.trendWeight {
                    Label(GoalText.weight(trend: t, goal: goalWeight, ratePerWeek: b.ratePerWeek), systemImage: "flag.checkered")
                        .font(.subheadline)
                }
                Text("Trend weight is a moving average of your weigh-ins, so water and food swings from one day to the next don't look like real change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    MetricTile(label: "Body fat", value: fmt(b.bodyFat, 1, "%"))
                    MetricTile(label: "Lean mass", value: fmt(b.leanMass, 1, " kg"),
                               detail: b.leanRatePerMonth.map { String(format: "%+.1f kg per month", $0) })
                }
                if b.muscleMass != nil {
                    HStack {
                        MetricTile(label: "Muscle", value: fmt(b.muscleMass, 1, " kg"),
                                   detail: b.muscleRatePerMonth.map { String(format: "%+.1f kg per month", $0) })
                        MetricTile(label: "Water", value: fmt(b.waterPercent, 0, "%"), detail: "of weight")
                        MetricTile(label: "Visceral fat", value: fmt(b.visceralFat, 0), detail: "Withings index")
                    }
                }
            } else {
                Text("No weigh-ins yet. Turn on Apple Health sync in the Withings app.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

struct NutritionCard: View {
    let model: DashboardModel
    @AppStorage(AppSettings.weightGoalKey) private var weightGoal = AppSettings.defaultWeightGoal

    var body: some View {
        Card(title: "Nutrition, last 7 days", systemImage: "fork.knife") {
            if let n = model.nutrition, n.daysLogged > 0 {
                HStack {
                    MetricTile(label: "Intake", value: fmt(n.avgIntake, 0, " kcal"), detail: "\(n.daysLogged) days logged")
                    MetricTile(label: "Burn", value: fmt(n.avgExpenditure, 0, " kcal"),
                               detail: n.expenditureIsAdaptive ? "adaptive, 28 days" : "watch estimate")
                    MetricTile(label: "Balance", value: n.balance.map { String(format: "%+.0f kcal", $0) } ?? "--")
                }
                HStack {
                    MetricTile(label: "Protein", value: fmt(n.proteinPerKg, 1, " g/kg"),
                               detail: fmt(n.avgProtein, 0, " g per day"))
                    MetricTile(label: "For your goal", value: fmt(n.suggestedIntake(kgPerWeek: weightGoal), 0, " kcal"),
                               detail: String(format: "%+.2f kg/week", weightGoal))
                    MetricTile(label: "Trend weight", value: n.tdee.map { String(format: "%+.2f kg", $0.trendPerWeek) } ?? "--",
                               detail: "per week")
                }
                macroLine(n)
                if let m = n.meals {
                    Text(mealText(m)).font(.subheadline)
                }
                if n.expenditureIsAdaptive {
                    Text("Burn comes from what you ate and how your trend weight moved, at 7700 kcal per kg. That figure is an approximation, and lean gain stores less energy per kg.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("An adaptive burn estimate appears after 14 logged days and 8 weigh-ins in 4 weeks.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No food logged in Apple Health. Any food app that writes calories and protein to Health will show up here.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    /// Grams per day with each macro's share of energy (4, 9 and 4 kcal per gram, the Atwater factors).
    @ViewBuilder
    private func macroLine(_ n: NutritionResult) -> some View {
        if let p = n.avgProtein, let f = n.avgFat, let c = n.avgCarbs {
            let total = max(p * 4 + f * 9 + c * 4, 1)
            let share = { (kcal: Double) in "\(Int((kcal / total * 100).rounded()))%" }
            VStack(alignment: .leading, spacing: 2) {
                Text("Protein \(Int(p)) g (\(share(p * 4))), fat \(Int(f)) g (\(share(f * 9))), carbs \(Int(c)) g (\(share(c * 4)))")
                if n.avgFiber != nil || n.avgSugar != nil {
                    Text("Fiber " + fmt(n.avgFiber, 0, " g") + ", sugar " + fmt(n.avgSugar, 0, " g") + " per day")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
    }

    private func mealText(_ m: MealTiming) -> String {
        let minutes = Int(m.lastMealMinutes.rounded()) % 1440
        let clock = String(format: "%02d:%02d", minutes / 60, minutes % 60)
        let gap = m.gapHours.formatted(.number.precision(.fractionLength(1)))
        return "Last meal around \(clock), \(gap) h before sleep. \(m.lateNights) of \(m.nights) nights under 3 h."
    }
}
