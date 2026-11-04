import SwiftUI
import SwiftData
import Charts
import HealthCore

/// Today answers one question first, how hard to go today, as claim, evidence, action. Everything else is a
/// one-line summary that opens its full card (progressive disclosure, so the screen stays light to read).
struct TodayView: View {
    let model: DashboardModel
    @State private var showSettings = false
    @AppStorage(AppSettings.todayStyleKey) private var todayStyle = "habits"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let msg = model.errorMessage {
                        Text(msg).foregroundStyle(.red).font(.subheadline)
                    }
                    RecoveryHero(model: model)
                    OvernightVitals(model: model)
                    TodayTrends(model: model)
                    NextDaysStrip(model: model)
                }
                .padding()
            }
            .background(AmbientBackground(tint: todayStyle == "balance" ? nil : model.dayStatus?.color))
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).day().month()))
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
                    .onDisappear { Task { await model.refresh() } }
            }
            .refreshable { await model.refresh() }
            .overlay {
                if model.isLoading && model.recovery == nil { ProgressView() }
            }
        }
    }
}

/// The balance blobs (sleep, food, strain), today's recovery, then the day's call as claim, evidence and action.
struct RecoveryHero: View {
    let model: DashboardModel
    @State private var open: BlobPart.Kind?
    @State private var openRecovery = false
    @AppStorage(AppSettings.weightGoalKey) private var weightGoal = AppSettings.defaultWeightGoal
    @AppStorage(AppSettings.proteinKey) private var proteinTarget = AppSettings.defaultProtein
    @AppStorage(AppSettings.todayStyleKey) private var style = "habits"


    private var night: SleepNight? { model.sleep.flatMap { $0.lastNight ?? $0.latestNight } }

    var body: some View {
        let r = model.recovery
        let color = r?.zone?.color ?? .gray
        VStack(alignment: .leading, spacing: 14) {
            if style == "balance" {
                let b = balance
                BlobCluster(parts: blobParts(b), headline: fmt(b?.score, 0), caption: "Balance") { open = $0 }
                Text("Last night's sleep (45%), yesterday's food (30%) and strain (25%), each scored 0 to 100.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                let status = model.dayStatus
                BlobCluster(parts: dayParts(r), headline: status?.word ?? "--", caption: "sleep · recovery · strain",
                            mergedTint: status?.color ?? .gray) { open = $0 }
            }
            if style == "balance" {
            Button { openRecovery = true } label: {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text("Recovery").font(.subheadline.weight(.semibold))
                    Text(fmt(r?.score, 0)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(color)
                    Text(r?.zone?.title.lowercased() ?? "calibrating").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            }

            if let c = model.coach {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.headline).font(.headline)
                    Text(confidence(r)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let r, r.score != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let cap = cappedReason(r) {
                        Label(cap, systemImage: "hand.raised.fill")
                            .foregroundStyle(Zone.moderate.color)
                    }
                    let shown = r.drivers.filter { abs($0.goodZ) >= 0.5 }.prefix(3)
                    if shown.isEmpty {
                        Label("Every signal is close to your normal.", systemImage: "equal.circle")
                    }
                    ForEach(Array(shown)) { d in
                        Label(DriverText.sentence(d), systemImage: d.goodZ > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(d.goodZ > 0 ? Zone.push.color : Zone.recover.color, .primary)
                    }
                }
                .font(.subheadline)
            }
            if let action = actionLine {
                Label(action, systemImage: "target").font(.subheadline)
            }
            if let bed = bedtimeLine {
                Label(bed, systemImage: "moon.zzz").font(.subheadline)
            }
            if style != "balance" {
                FoodSliders(model: model, proteinTarget: proteinTarget) { open = .food }
                HabitStrip(habits: model.habits, proteinTarget: proteinTarget) { open = $0 }
            }
            FeelCheckIn()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(16)
        .navigationDestination(isPresented: $openRecovery) { DetailPage(title: "Recovery") { RecoveryDetail(model: model) } }
        .navigationDestination(item: $open) { kind in
            switch kind {
            case .sleep: SleepDetailView(model: model)
            case .food: NutritionDetailView(model: model)
            case .recovery: DetailPage(title: "Recovery") { RecoveryDetail(model: model) }
            case .strain:
                DetailPage(title: "Training") {
                    TrainingCard(model: model)
                    StrainExplanation(model: model)
                }
            }
        }
    }

    /// Last night's sleep and yesterday's food and strain, merged into the balance score.
    private var balance: BalanceScore? {
        BalanceEngine.evaluate(model.snapshot, day: Calendar.current.startOfDay(for: .now),
                               sleepScore: night.map { model.sleepScore(for: $0).score }, training: model.training,
                               recovery: model.recoveryHistory.isEmpty ? model.scoreHistory : model.recoveryHistory,
                               weightKg: model.bodyComp?.trendWeight,
                               goalIntake: model.nutrition?.suggestedIntake(kgPerWeek: weightGoal), proteinTarget: proteinTarget)
    }

    /// Sleep, recovery and strain, the three dials as blobs: sleep score and recovery out of 100, strain out of 21.
    private func dayParts(_ r: RecoveryResult?) -> [BlobPart] {
        let sleep = night.map { model.sleepScore(for: $0).score }
        let strain = model.training?.today?.strain ?? (model.training?.tau == nil ? nil : 0)
        let zone = r?.zone?.color ?? .gray
        return [
            BlobPart(kind: .sleep, fraction: (sleep ?? 0) / 100, value: fmt(sleep, 0), label: "sleep",
                     colors: [Palette.sleep, Palette.sleep.lighter(0.45)]),
            BlobPart(kind: .recovery, fraction: (r?.score ?? 0) / 100, value: fmt(r?.score, 0), label: "recovery",
                     colors: [zone, zone.lighter(0.45)]),
            BlobPart(kind: .strain, fraction: (strain ?? 0) / 21, value: strain.map { String(format: "%.1f", $0) } ?? "--",
                     label: "strain", colors: [Palette.strain, Palette.strain.lighter(0.45)]),
        ]
    }

    /// The balance's parts as blobs, each sized by its score.
    private func blobParts(_ b: BalanceScore?) -> [BlobPart] {
        let part = { (p: BalanceScore.Part, kind: BlobPart.Kind, label: String, color: Color) -> BlobPart in
            let v = b?.score(p)
            return BlobPart(kind: kind, fraction: (v ?? 0) / 100, value: fmt(v, 0), label: label, colors: [color, color.lighter(0.45)])
        }
        return [part(.sleep, .sleep, "sleep", Palette.sleep), part(.food, .food, "food", Palette.nutrition),
                part(.strain, .strain, "strain", Palette.strain)]
    }

    /// How much to trust today's verdict, said up front.
    private func confidence(_ r: RecoveryResult?) -> String {
        guard let r, r.score != nil else { return "Recovery needs 14 nights with your watch" }
        return r.personalZones ? "Zones from your last 30 days" : "Generic zones until 14 days of scores"
    }

    /// When a safety gate lowered the zone, the ring's number alone would mislead, so say why first.
    private func cappedReason(_ r: RecoveryResult) -> String? {
        guard let score = r.score, let zone = r.zone else { return nil }
        let byScore: Zone = score < r.low ? .recover : (score >= r.high ? .push : .moderate)
        guard zone < byScore else { return nil }
        let reason = r.reasons.first ?? ""
        return "Held at \(zone.title.lowercased()): \(reason.prefix(1).lowercased() + reason.dropFirst())"
    }

    /// Tonight's bedtime for the wake goal: sleep need stretched by your usual efficiency (`SleepPlan.bedtime`).
    private var bedtimeLine: String? {
        let wake = UserDefaults.standard.object(forKey: AppSettings.wakeGoalKey) as? Double ?? AppSettings.defaultWakeGoal
        let need = UserDefaults.standard.object(forKey: AppSettings.sleepNeedKey) as? Double ?? 8
        guard let eff = SleepPlan.efficiency(model.snapshot.sleep) else { return nil }
        let bed = SleepPlan.bedtime(wake: wake, needHours: need, efficiency: eff)
        return "In bed by \(SleepPlanText.clock(bed)) tonight to wake at \(SleepPlanText.clock(wake)) with \(need.formatted(.number.precision(.fractionLength(0...2)))) h asleep."
    }

    private var actionLine: String? {
        guard let t = model.training?.strainTarget else { return nil }
        return "Aim for a day strain of \(Int(t.lowerBound.rounded())) to \(Int(t.upperBound.rounded())) today."
    }
}

enum DriverText {
    static func name(_ i: RecoveryDriver.Input) -> String {
        switch i {
        case .hrv: "HRV"
        case .restingHR: "Resting heart rate"
        case .breathing: "Breathing rate"
        case .sleep: "Sleep"
        }
    }

    static func value(_ v: Double, _ i: RecoveryDriver.Input) -> String {
        switch i {
        case .hrv: "\(Int(v.rounded())) ms"
        case .restingHR: "\(Int(v.rounded())) bpm"
        case .breathing: String(format: "%.1f /min", v)
        case .sleep: String(format: "%.1f h", v)
        }
    }

    /// Contrastive: today against your own normal, not against a population.
    static func sentence(_ d: RecoveryDriver) -> String {
        let dir = d.value >= d.typical ? "above" : "below"
        return "\(name(d.input)) \(value(d.value, d.input)), \(dir) your usual \(value(d.typical, d.input))"
    }
}

/// A full card on its own page.
struct DetailPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) { content() }.padding()
        }
        .background(AmbientBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Everything behind the verdict: the inputs, every reason and the zone cutoffs.
struct RecoveryDetail: View {
    let model: DashboardModel

    var body: some View {
        let r = model.recovery
        if let r, let score = r.score, !r.drivers.isEmpty {
            RecoveryBreakdown(score: score, drivers: r.drivers)
        }
        AgreementCard(scores: model.recoveryHistory.isEmpty ? model.scoreHistory : model.recoveryHistory)
        Card(title: "Inputs", systemImage: "bolt.heart") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    MetricTile(label: "HRV", value: fmt(r?.hrv, 0, " ms"), detail: zText(r?.hrvZ))
                    MetricTile(label: "Resting HR", value: fmt(r?.rhr, 0, " bpm"), detail: zText(r?.rhrZ))
                }
                GridRow {
                    MetricTile(label: "Breathing", value: fmt(r?.rr, 1, " /min"), detail: zText(r?.rrZ))
                    MetricTile(label: "Sleep", value: fmt(r?.sleepHours, 1, " h"))
                }
            }
        }
        Card(title: "Reasons", systemImage: "list.bullet") {
            ForEach(r?.reasons ?? [], id: \.self) { reason in
                Label(reason, systemImage: "info.circle").font(.subheadline)
            }
            if let notes = model.coach?.notes, !notes.isEmpty {
                Divider()
                ForEach(notes, id: \.self) { Label($0, systemImage: "arrow.turn.down.right").font(.subheadline) }
            }
        }
        if let r, r.score != nil {
            Card(title: "Zones", systemImage: "slider.horizontal.below.rectangle") {
                Text("Under \(Int(r.low)) means recover, \(Int(r.high)) and up means push. \(r.personalZones ? "These are your own 25th and 75th percentiles over 30 days." : "Generic cutoffs until you have 14 days of scores.")")
                    .font(.subheadline)
            }
        }
    }
}
struct SettingsView: View {
    let model: DashboardModel
    @AppStorage(AppSettings.sleepNeedKey) private var sleepNeed = 8.0
    @AppStorage(AppSettings.proteinKey) private var protein = AppSettings.defaultProtein
    @AppStorage(AppSettings.historyDaysKey) private var historyDays = AppSettings.defaultHistoryDays
    @AppStorage(AppSettings.weightGoalKey) private var weightGoal = AppSettings.defaultWeightGoal
    @AppStorage(AppSettings.todayStyleKey) private var todayStyle = "habits"
    @AppStorage(AppSettings.wakeGoalKey) private var wakeGoal = AppSettings.defaultWakeGoal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Sleep need: \(sleepNeed.formatted(.number.precision(.fractionLength(0...2)))) h",
                            value: $sleepNeed, in: 6...10, step: 0.25)
                    DatePicker("Wake-up goal", selection: Binding(
                        get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(wakeGoal * 60) },
                        set: { wakeGoal = SleepPlan.clock($0) }), displayedComponents: .hourAndMinute)
                    if let usual = SleepPlan.usualWake(model.snapshot.sleep), abs(usual - wakeGoal) >= 5 {
                        Button("Use my usual wake time, \(SleepPlanText.clock(usual))") { wakeGoal = usual }
                    }
                    if let eff = SleepPlan.efficiency(model.snapshot.sleep) {
                        LabeledContent("Bedtime for that", value: SleepPlanText.clock(SleepPlan.bedtime(wake: wakeGoal, needHours: sleepNeed, efficiency: eff)))
                    }
                } header: {
                    Text("Sleep")
                } footer: {
                    Text("Apple Health doesn't share the Sleep Schedule from the Health app, so set your wake-up time here. Bedtime is your sleep need stretched by how much of your time in bed you usually sleep.")
                }
                Section {
                    Picker("Main blob", selection: $todayStyle) {
                        Text("Day indicator and habits").tag("habits")
                        Text("Balance").tag("balance")
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text(todayStyle == "habits" ? "The blob turns green, yellow or red from sleep, recovery and strain, and splits into those three. Food bars and habit trackers sit below." :
                            "The blob is a balance score of last night's sleep and yesterday's food and strain.")
                }
                Section("Nutrition") {
                    Stepper(String(format: "Protein target: %.1f g/kg", protein),
                            value: $protein, in: 1.0...2.5, step: 0.1)
                    Stepper(String(format: "Weight goal: %+.2f kg/week", weightGoal),
                            value: $weightGoal, in: -0.75...0.75, step: 0.05)
                }
                Section {
                    Picker("History", selection: $historyDays) {
                        ForEach(AppSettings.historyOptions, id: \.days) { Text($0.label).tag($0.days) }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    if let t = model.fetchSeconds {
                        Text("Last refresh took \(t.formatted(.number.precision(.fractionLength(1)))) s. Longer history makes refreshes slower.")
                    }
                }
                Section("From Apple Health") {
                    LabeledContent("Age", value: model.snapshot.profile.age(on: .now).map { "\($0)" } ?? "Not shared")
                    LabeledContent("Sex", value: sexText(model.snapshot.profile.sex))
                }
                StrongImportSection(model: model)
                WithingsSection(model: model)
                ScaleImportSection(model: model)
                Section("Your data") {
                    NavigationLink("Export data") { ExportView(model: model) }
                    NavigationLink("Assistant") { AssistantSettingsView() }
                }
                #if DEBUG
                Section("Debug") {
                    NavigationLink("Awakening calibration") { AwakeningCalibrationView(model: model) }
                }
                #endif
                Section("Data sources") {
                    Text("Apple Watch: HRV, resting heart rate, sleep, workouts and energy.")
                    Text("Smart scale: weight, body fat and lean mass from any scale app that writes to Apple Health; more from the Withings API or a CSV export.")
                    Text("Food: any app that writes nutrition to Apple Health, like Cronometer, MyFitnessPal or Lose It.")
                    Text("Lifting: Strong or Hevy CSV exports.")
                }
                .font(.footnote)
            }
            .ambientList()
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func sexText(_ sex: Sex?) -> String {
        switch sex {
        case .male?: "Male"
        case .female?: "Female"
        case nil: "Not shared"
        }
    }
}

/// Where today's score came from: a waterfall from a normal morning (50) through each input's exact Shapley
/// share to today's score, then what-if lines and the model's assumptions.
struct RecoveryBreakdown: View {
    let score: Double
    let drivers: [RecoveryDriver]

    private struct Step: Identifiable {
        let label: String
        let start: Double
        let end: Double
        let kind: Int     // 0 anchor, 1 helps, 2 hurts
        var id: String { label }
    }

    private var steps: [Step] {
        let parts = RecoveryEngine.breakdown(drivers).sorted { abs($0.points) > abs($1.points) }
        var running = 50.0
        var out = [Step(label: "Normal morning", start: 0, end: 50, kind: 0)]
        for p in parts {
            out.append(Step(label: DriverText.name(p.input), start: running, end: running + p.points, kind: p.points >= 0 ? 1 : 2))
            running += p.points
        }
        out.append(Step(label: "Today", start: 0, end: score, kind: 0))
        return out
    }

    var body: some View {
        Card(title: "Breakdown", systemImage: "chart.bar.xaxis") {
            Text("A morning where every input sits at your normal scores 50. Each bar is how far one input moved today away from that.")
                .font(.subheadline)
            Chart(steps) { s in
                BarMark(xStart: .value("From", min(s.start, s.end)), xEnd: .value("To", max(s.start, s.end)),
                        y: .value("Input", s.label))
                    .foregroundStyle(s.kind == 0 ? Color.secondary.opacity(0.35) : (s.kind == 1 ? Zone.push.color : Zone.recover.color))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(s.kind == 0 ? "\(Int(s.end.rounded()))" : String(format: "%+.0f", s.end - s.start))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis { AxisMarks(values: [0, 50, 100]) }
            .frame(height: CGFloat(steps.count) * 34)
            Text("Shapley values: each input's average effect over every order the inputs could be added in, so the bars add up exactly to today's score. Safety caps on the zone are not part of the score; see Reasons.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Card(title: "What if", systemImage: "arrow.triangle.branch") {
            ForEach(drivers) { d in
                let alt = RecoveryEngine.whatIf(drivers, normal: d.input)
                HStack {
                    Text("\(DriverText.name(d.input)) at your usual \(DriverText.value(d.typical, d.input))")
                    Spacer()
                    Text("\(Int(alt.rounded()))").monospacedDigit().fontWeight(.semibold)
                    Text(String(format: "%+.0f", alt - score))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.subheadline)
            }
            Text("Each line changes one input and keeps the others as they were. In real life they move together: a short night often lowers HRV too.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Each morning: how do you feel, before looking too closely at the score. Pick a number, confirm, and it goes
/// away for the day. It is the ground truth the score is checked against, and an outcome for Insights.
struct FeelCheckIn: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [JournalEntry]
    @State private var pending: Int?

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var saved: Int? { entries.first { $0.day == today }?.feel }

    var body: some View {
        if saved == nil {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("How do you feel this morning?").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("drained").font(.caption2).foregroundStyle(.secondary)
                    ForEach(1...5, id: \.self) { v in
                        Button { pending = v } label: {
                            Text("\(v)")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(pending == v ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                                .foregroundStyle(pending == v ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Feel \(v) of 5")
                    }
                    Text("great").font(.caption2).foregroundStyle(.secondary)
                }
                if let p = pending {
                    Button("Save \(p) of 5") { save(p) }
                        .glassButton(prominent: true)
                        .controlSize(.small)
                }
            }
            .transition(.opacity)
        }
    }

    private func save(_ v: Int) {
        withAnimation {
            if let e = entries.first(where: { $0.day == today }) {
                e.feel = v
            } else {
                let e = JournalEntry(day: today)
                e.feel = v
                context.insert(e)
            }
            pending = nil
        }
    }
}

/// Does the score match how you feel? Spearman's rho between your morning ratings and the scores.
struct AgreementCard: View {
    let scores: [DailyValue]
    @Query private var entries: [JournalEntry]

    var body: some View {
        let feel = entries.feelSeries
        Card(title: "Does it match how you feel?", systemImage: "person.fill.checkmark") {
            if let e = entries.first(where: { $0.day == Calendar.current.startOfDay(for: .now) }), let f = e.feel {
                HStack {
                    Text("This morning you said \(f) of 5.")
                    Spacer()
                    Button("Change") { e.feel = nil }.font(.subheadline)
                }
                .font(.subheadline)
            }
            if let a = CheckInEngine.agreement(feel: feel, scores: scores) {
                HStack {
                    MetricTile(label: "Agreement", value: String(format: "%.2f", a.rho), detail: "rank correlation")
                    MetricTile(label: "95% range", value: String(format: "%.2f to %.2f", a.ci.lowerBound, a.ci.upperBound))
                    MetricTile(label: "Mornings", value: "\(a.n)")
                }
                Text(verdict(a)).font(.subheadline)
            } else {
                let rated = feel.count
                Text("Rate how you feel on Today each morning. After \(CheckInEngine.minMornings) mornings this shows whether the score tracks it (\(rated) so far).")
                    .font(.subheadline)
            }
            Text("1 means a perfect match in order, 0 no relation. Your rating is the real test of the score. If they disagree for weeks, trust how you feel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func verdict(_ a: Agreement) -> String {
        if a.ci.lowerBound > 0.3 { return "The score tracks how you feel." }
        if a.ci.lowerBound > 0 { return "The score tracks how you feel, loosely." }
        if a.ci.upperBound < 0 { return "The score runs against how you feel. Worth a closer look." }
        return "No clear relation yet. More mornings will tell."
    }
}

/// Trends chosen for Today, as the same small multiples as the Trends tab, over the last 30 days.
struct TodayTrends: View {
    let model: DashboardModel
    @AppStorage("todayTrends") private var stored = TrendMetric.defaultToday.map(\.rawValue).joined(separator: ",")
    @State private var editing = false

    private var chosen: [TrendMetric] {
        let set = Set(stored.split(separator: ",").map(String.init))
        return TrendMetric.recommended.filter { set.contains($0.rawValue) && !TrendRange.month.shown($0.values(model)).isEmpty }
    }
    private var domain: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .day, value: -29, to: today)!...today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your trends: latest, against 30 days").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Edit") { editing = true }
                    .font(.caption)
                    .glassButton()
                    .controlSize(.mini)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(chosen) { m in
                    NavigationLink {
                        MetricDetailView(model: model, metric: m, range: .month)
                    } label: {
                        SmallMultiple(metric: m, points: TrendRange.month.shown(m.values(model)), domain: domain, range: .month, latest: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $editing) { TrendPicker(stored: $stored) }
    }
}

/// Choose Today's trends. Listed in recommended order, each with why it is (or isn't) worth watching.
struct TrendPicker: View {
    @Binding var stored: String
    @Environment(\.dismiss) private var dismiss

    private var set: Set<String> { Set(stored.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(TrendMetric.recommended.enumerated()), id: \.element) { i, m in
                        Button { toggle(m) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: set.contains(m.rawValue) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(set.contains(m.rawValue) ? m.color : Color.secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(m.name).foregroundStyle(.primary)
                                        if i < 4 {
                                            Text("Recommended").font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(m.color.opacity(0.15), in: Capsule())
                                                .foregroundStyle(m.color)
                                        }
                                    }
                                    Text(m.why).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Ordered by how accurate the measurement is and how much it says about recovery and lean gain.")
                }
            }
            .ambientList()
            .navigationTitle("Your trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { stored = TrendMetric.defaultToday.map(\.rawValue).joined(separator: ",") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func toggle(_ m: TrendMetric) {
        var s = set
        if s.contains(m.rawValue) { s.remove(m.rawValue) } else { s.insert(m.rawValue) }
        stored = TrendMetric.recommended.filter { s.contains($0.rawValue) }.map(\.rawValue).joined(separator: ",")
    }
}

extension DashboardModel {
    /// Good, steady or take it easy, from last night's sleep, today's recovery and today's strain.
    var dayStatus: DayStatus? {
        let night = sleep.flatMap { $0.lastNight ?? $0.latestNight }
        return DayStatus.evaluate(sleepScore: night.map { sleepScore(for: $0).score }, zone: recovery?.zone,
                                  strain: training?.today?.strain, target: training?.strainTarget)
    }
}

extension DayStatus {
    var word: String {
        switch self {
        case .good: "Good"
        case .steady: "Steady"
        case .takeItEasy: "Easy"
        }
    }

    var color: Color {
        switch self {
        case .good: Palette.good
        case .steady: Palette.caution
        case .takeItEasy: Palette.bad
        }
    }
}
