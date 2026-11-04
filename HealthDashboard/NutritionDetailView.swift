import SwiftUI
import Charts
import HealthCore

/// Nutrition overview: energy against burn and goal, protein against target, macro split and meal timing.
struct NutritionDetailView: View {
    let model: DashboardModel
    @AppStorage(AppSettings.proteinKey) private var proteinTarget = AppSettings.defaultProtein
    @AppStorage(AppSettings.weightGoalKey) private var weightGoal = AppSettings.defaultWeightGoal
    @State private var range = Range.week

    enum Range: String, CaseIterable {
        case week = "Week", month = "Month", quarter = "3 months"
        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
    }
    private var days: [NutritionDay] { NutritionEngine.daily(model.snapshot, days: range.days, endingOn: yesterday) }
    private var weight: Double? { model.bodyComp?.trendWeight ?? model.snapshot.weight.last?.value }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NutritionCard(model: model)
                FoodQualityCard(model: model)
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                if days.isEmpty {
                    Text("No food logged in this period.").foregroundStyle(.secondary)
                } else {
                    averagesCard
                    energyCard
                    proteinCard
                    macroCard
                }
                mealCard
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mean(_ k: KeyPath<NutritionDay, Double?>) -> Double? { Stats.mean(days.compactMap { $0[keyPath: k] }) }

    private var averagesCard: some View {
        Card(title: "Daily average", systemImage: "chart.bar.doc.horizontal") {
            let kcal = Stats.mean(days.map(\.kcal))
            let protein = mean(\.protein)
            HStack {
                MetricTile(label: "Intake", value: fmt(kcal, 0, " kcal"), detail: "\(days.count) of \(range.days) days logged")
                MetricTile(label: "Protein", value: fmt(protein.flatMap { p in weight.map { p / $0 } }, 1, " g/kg"),
                           detail: "target " + fmt(proteinTarget, 1))
                MetricTile(label: "For your goal", value: fmt(model.nutrition?.suggestedIntake(kgPerWeek: weightGoal), 0, " kcal"),
                           detail: String(format: "%+.2f kg/week", weightGoal))
            }
            HStack {
                MetricTile(label: "Fat", value: fmt(mean(\.fat), 0, " g"))
                MetricTile(label: "Carbs", value: fmt(mean(\.carbs), 0, " g"))
                MetricTile(label: "Fiber", value: fmt(mean(\.fiber), 0, " g"))
                MetricTile(label: "Sugar", value: fmt(mean(\.sugar), 0, " g"))
            }
        }
    }

    private var energyCard: some View {
        Card(title: "Energy", systemImage: "flame") {
            let start = days.first?.date ?? yesterday
            let burn = model.tdeeHistory.filter { $0.date >= start }
            let goal = model.nutrition?.suggestedIntake(kgPerWeek: weightGoal)
            Chart {
                ForEach(days) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.kcal))
                        .foregroundStyle(by: .value("Series", "Intake"))
                }
                ForEach(burn) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("kcal", p.value))
                        .foregroundStyle(by: .value("Series", "Burn"))
                        .interpolationMethod(.monotone)
                }
                if let goal {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartForegroundStyleScale(["Intake": Palette.nutrition, "Burn": Color.secondary])
            .frame(height: 180)
            Text(goal == nil ? "Burn is the adaptive estimate; it appears after 14 logged days and 8 weigh-ins."
                             : "Dashed line: intake for your weight goal.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var proteinCard: some View {
        Card(title: "Protein", systemImage: "fish") {
            if let w = weight {
                Chart {
                    ForEach(days.filter { $0.protein != nil }) { d in
                        BarMark(x: .value("Day", d.date, unit: .day), y: .value("g/kg", d.protein! / w))
                            .foregroundStyle((d.protein! / w >= proteinTarget ? Palette.good : Palette.caution).gradient)
                    }
                    RuleMark(y: .value("Target", proteinTarget))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .frame(height: 160)
                let hit = days.filter { ($0.protein ?? 0) / w >= proteinTarget }.count
                Text("Target reached on \(hit) of \(days.count) logged days, per kg of trend weight.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Needs a weigh-in to show protein per kg.").foregroundStyle(.secondary)
            }
        }
    }

    /// Energy from each macro with the Atwater factors: 4 kcal per g protein and carbs, 9 per g fat.
    private var macroCard: some View {
        Card(title: "Macro split", systemImage: "chart.pie") {
            let rows = days.flatMap { d -> [(Date, String, Double)] in
                guard let p = d.protein, let f = d.fat, let c = d.carbs else { return [] }
                return [(d.date, "Protein", p * 4), (d.date, "Fat", f * 9), (d.date, "Carbs", c * 4)]
            }
            if rows.isEmpty {
                Text("Your food app doesn't write fat and carbs to Apple Health.").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        BarMark(x: .value("Day", r.0, unit: .day), y: .value("kcal", r.2))
                            .foregroundStyle(by: .value("Macro", r.1))
                    }
                }
                .chartForegroundStyleScale(["Protein": Color.red, "Fat": Color.yellow, "Carbs": Color.blue])
                .frame(height: 180)
                let total = rows.reduce(0) { $0 + $1.2 }
                let share = { (m: String) in Int((rows.filter { $0.1 == m }.reduce(0) { $0 + $1.2 } / max(total, 1) * 100).rounded()) }
                Text("Protein \(share("Protein"))%, fat \(share("Fat"))%, carbs \(share("Carbs"))% of energy")
                    .font(.subheadline)
            }
        }
    }

    private var mealCard: some View {
        Card(title: "Last meal before sleep", systemImage: "clock") {
            let since = Calendar.current.date(byAdding: .day, value: -range.days, to: Calendar.current.startOfDay(for: .now))!
            let nights = model.snapshot.sleep.filter { $0.date > since }
            let last = NutritionEngine.lastMeals(NutritionEngine.meals(model.snapshot.foodLog), nights: nights)
            if last.isEmpty {
                Text("No meal times found. Meal timing uses the last 60 days of food entries.").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(last) { m in
                        BarMark(x: .value("Night", m.night, unit: .day), y: .value("h", m.gapHours))
                            .foregroundStyle((m.gapHours < 3 ? Palette.caution : Palette.sleep).gradient)
                    }
                    RuleMark(y: .value("3 h", 3))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartYAxisLabel("hours from last meal to sleep")
                .frame(height: 160)
                Text("\(last.filter { $0.gapHours < 3 }.count) of \(last.count) nights under 3 h.")
                    .font(.subheadline)
                if NutritionEngine.isHourly(model.snapshot.foodLog) {
                    Text("Your food app logs by the hour, so each meal is placed mid-hour. Times are good to about 30 minutes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Yesterday's food against a target for every nutrient Apple Health stores, and the limits that cost points.
struct FoodQualityCard: View {
    let model: DashboardModel
    @AppStorage(AppSettings.proteinKey) private var proteinTarget = AppSettings.defaultProtein
    @State private var showAll = false

    private var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))! }

    var body: some View {
        let s = model.snapshot
        let q = DietQualityEngine.score(s, on: yesterday, proteinTarget: model.bodyComp?.trendWeight.map { $0 * proteinTarget })
        Card(title: "Food quality, yesterday", systemImage: "leaf") {
            if let q {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(q.score.rounded()))").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Palette.nutrition)
                    Text("of 100").foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "targets %.0f%%", q.encourage)).font(.caption).foregroundStyle(.secondary)
                        if q.penalty > 0 {
                            Text(String(format: "−%.0f over limits", q.penalty)).font(.caption.weight(.semibold)).foregroundStyle(Palette.bad)
                        }
                    }
                }
                let over = q.nutrients.filter { $0.isLimit && $0.penalty > 0 }
                if !over.isEmpty {
                    Text("Over the limit").font(.caption.weight(.semibold)).foregroundStyle(Palette.bad)
                    ForEach(over) { row($0) }
                }
                let targets = q.nutrients.filter { !$0.isLimit }.sorted { $0.percent < $1.percent }
                Text("Targets, lowest first").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(showAll ? targets : Array(targets.prefix(6))) { row($0) }
                if targets.count > 6 {
                    Button(showAll ? "Show fewer" : "Show all \(targets.count) nutrients") { withAnimation { showAll.toggle() } }
                        .font(.caption)
                }
                if showAll {
                    let limits = q.nutrients.filter { $0.isLimit && $0.penalty == 0 }
                    if !limits.isEmpty {
                        Text("Limits kept").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(limits) { row($0) }
                    }
                }
                Text("Targets are your protein goal, fiber per calorie and the US daily values Cronometer's defaults start from. Limits cost half a point per percent over: sodium, saturated and total fat, sugar, cholesterol, caffeine, and upper intake levels for vitamins and minerals.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Needs yesterday's calories and at least 4 nutrients with a target.").font(.subheadline).foregroundStyle(.secondary)
            }
            let c = DietQualityEngine.coverage(s, on: yesterday)
            Text("\(c.seen) of \(c.total) Apple Health nutrients arrived for yesterday. Cronometer and MyFitnessPal choose what they share in their Apple Health settings; their own goals can't be read.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func row(_ n: NutrientScore) -> some View {
        let color: Color = n.isLimit ? (n.penalty > 0 ? Palette.bad : Color.secondary.opacity(0.5))
                                     : (n.percent >= 100 ? Palette.good : (n.percent >= 50 ? Palette.caution : Palette.bad))
        return HStack(spacing: 8) {
            Text(n.name + (n.isLimit && !["Sodium", "Cholesterol", "Caffeine", "Saturated fat", "Fat", "Sugar"].contains(n.name) ? " (upper)" : ""))
                .font(.caption).lineLimit(1).frame(width: 118, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(color).frame(width: g.size.width * min(1, n.percent / (n.isLimit ? 150 : 100)))
                    if n.isLimit { Rectangle().fill(Color.secondary).frame(width: 1).offset(x: g.size.width * 100 / 150) }
                }
            }
            .frame(height: 7)
            Text("\(Int(n.percent.rounded()))%").font(.caption2).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }
}
