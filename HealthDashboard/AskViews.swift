import SwiftUI
import SwiftData
import HealthCore

/// Builds what is sent with a question: a short summary of what the app computed, plus the daily table.
enum AssistantContext {
    static let system = """
    You help one person understand their own health, sleep, training and nutrition data. It comes from an Apple Watch, \
    a Withings smart scale, Cronometer (food) and Strong (lifting), already summarized by their own app. Their goal is \
    lean muscle gain with strength training about every other day.
    Rules: use only the data given and say when it is too thin to answer. Correlation is not causation, so write \
    "your data suggests". Give concrete, practical suggestions. No medical diagnoses; for anything worrying, suggest a \
    doctor. Metric units, 24 h time, short paragraphs or bullets, no em dashes.
    """

    @MainActor
    static func build(_ m: DashboardModel, tags: [(day: Date, tags: [String])], feel: [DailyValue], days: Int) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        let s = m.snapshot
        var lines = ["Today is \(today.formatted(.iso8601.year().month().day())).",
                     "Profile: age \(s.profile.age(on: .now).map(String.init) ?? "unknown"), sex \(s.profile.sex.map { "\($0)" } ?? "unknown")."]
        if let r = m.recovery {
            lines.append("Recovery today: \(fmt(r.score, 0)) of 100 (\(r.zone?.title.lowercased() ?? "calibrating")). Personal zones: recover below \(fmt(r.low, 0)), push from \(fmt(r.high, 0)).")
            lines += r.reasons.map { "- " + $0 }
        }
        if let c = m.coach { lines.append("App's call today: \(c.headline)") ; lines += c.notes.map { "- " + $0 } }
        if let n = m.nutrition {
            lines.append("Nutrition, last 7 days: intake \(fmt(n.avgIntake, 0)) kcal, burn \(fmt(n.avgExpenditure, 0)) kcal (\(n.expenditureIsAdaptive ? "adaptive estimate" : "watch estimate")), protein \(fmt(n.proteinPerKg, 1)) g/kg.")
        }
        if let b = m.bodyComp {
            lines.append("Body: trend weight \(fmt(b.trendWeight, 1)) kg, changing \(fmt(b.ratePerWeek, 2)) kg/week, body fat \(fmt(b.bodyFat, 1))%.")
        }
        if let f = m.readiness, !f.days.isEmpty {
            lines.append("Recovery forecast (model beat the naive guess in backtests): " + f.days.map { "\($0.date.formatted(.dateTime.weekday(.abbreviated))) \(fmt($0.planned, 0))" }.joined(separator: ", "))
        }
        let report = InsightsEngine.report(s, recovery: m.scoreHistory, training: m.training?.days ?? [], lifts: m.lifts, tags: tags, feel: feel)
        if !report.findings.isEmpty {
            lines.append("Patterns the app found (weekday deconfounded, false discovery rate under 10%):")
            lines += report.findings.prefix(8).map { "- " + InsightText.headline($0) + ". " + InsightText.comparison($0) }
        }
        let table = DailyExport.table(s, recovery: m.recoveryHistory.isEmpty ? m.scoreHistory : m.recoveryHistory,
                                      training: m.training?.days ?? [], lifts: m.lifts, tags: tags,
                                      needHours: UserDefaults.standard.object(forKey: AppSettings.sleepNeedKey) as? Double ?? 8,
                                      days: days, endingOn: today, feel: feel)
        lines.append("")
        lines.append("Daily table, last \(days) days. Morning and sleep columns describe the night that ended that morning; the rest describe the day. Recovery is 0 to 100, strain 0 to 21, feel is the person's own morning rating from 1 (drained) to 5 (great).")
        lines.append(table.csv)
        return lines.joined(separator: "\n")
    }
}

struct AskView: View {
    let model: DashboardModel
    @Query private var entries: [JournalEntry]
    @AppStorage(AssistantConfig.enabledKey) private var enabled = false
    @AppStorage(AssistantConfig.daysKey) private var days = 30
    @AppStorage(AssistantConfig.providerKey) private var providerRaw = AssistantProvider.gemini.rawValue
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?

    private let suggestions = ["Why was my recovery lower this week?", "What could I change to sleep better?",
                               "How is my lean gain going?", "Am I eating enough protein on training days?"]

    /// Built once per range change: it runs the insights engine, too slow to redo on every redraw.
    @State private var context = ""

    var body: some View {
        VStack(spacing: 0) {
            if !enabled {
                optIn
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header
                            if messages.isEmpty {
                                ForEach(suggestions, id: \.self) { q in
                                    Button(q) { draft = q; send() }
                                        .buttonStyle(.bordered)
                                        .font(.subheadline)
                                }
                            }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            if sending { ProgressView().padding(.leading, 8) }
                            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        }
                        .padding()
                    }
                    .onChange(of: messages) { _, m in withAnimation { proxy.scrollTo(m.last?.id) } }
                }
                inputBar
            }
        }
        .background(AmbientBackground())
        .task(id: "\(days)|\(model.refreshCount)") {
            context = AssistantContext.build(model, tags: entries.map { (day: $0.day, tags: $0.tags) }, feel: entries.feelSeries, days: days)
        }
        .navigationTitle("Ask your data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink { AssistantSettingsView() } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Assistant settings")
        }
    }

    private var optIn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(title: "Sends data off your phone", systemImage: "icloud.and.arrow.up") {
                    Text("Your question goes to the provider you choose, together with a summary of your data: today's scores, the patterns the app found, and a daily table (sleep, recovery, training, food and body) for the last \(days) days. You can read exactly what is sent before asking.")
                    Text("Nothing is sent until you switch this on. Free tiers may use what you send to improve their models; check the provider's terms.")
                        .foregroundStyle(.secondary)
                    Toggle("Allow sending my data", isOn: $enabled)
                }
                .font(.subheadline)
            }
            .padding()
        }
    }

    private var header: some View {
        let c = AssistantConfig.current
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(c.provider.name), \(c.model.isEmpty ? "no model chosen" : c.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup("What is sent (about \((context.count / 4).formatted()) tokens)") {
                Picker("Days of data", selection: $days) {
                    ForEach([14, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal) {
                    Text(context).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                }
                .frame(maxHeight: 260)
            }
            .font(.caption)
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let r = m.reasoning {
                    DisclosureGroup("Reasoning") {
                        Text(r).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .font(.caption)
                }
                Text(LocalizedStringKey(m.text))   // renders the provider's Markdown bold and lists
                    .font(.subheadline)
            }
                .padding(10)
                .background(m.role == .user ? Theme.accent.opacity(0.15) : Color.white.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            if m.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("Ask about your data", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding()
        .background(.bar)
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, enabled, !context.isEmpty else { return }
        draft = ""
        error = nil
        messages.append(ChatMessage(role: .user, text: q))
        // The data rides along with the first question, as part of the instructions, so follow-ups stay short.
        let system = AssistantContext.system + "\n\n" + context
        let history = messages, config = AssistantConfig.current
        sending = true
        Task {
            defer { sending = false }
            do {
                let reply = try await AssistantClient.send(system: system, messages: history, config: config)
                messages.append(ChatMessage(role: .assistant, text: reply.answer, reasoning: reply.reasoning))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AssistantSettingsView: View {
    @AppStorage(AssistantConfig.enabledKey) private var enabled = false
    @AppStorage(AssistantConfig.providerKey) private var providerRaw = AssistantProvider.gemini.rawValue
    @State private var url = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var models: [String] = []
    @State private var status: String?
    @State private var loading = false

    private var provider: AssistantProvider { AssistantProvider(rawValue: providerRaw) ?? .gemini }

    var body: some View {
        Form {
            Section {
                Toggle("Allow sending my data", isOn: $enabled)
            } footer: {
                Text("Off means nothing leaves your phone.")
            }
            Section {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AssistantProvider.allCases) { Text($0.name).tag($0.rawValue) }
                }
                if provider.editableURL {
                    TextField("Address", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if provider.needsKey || provider == .custom {
                    SecureField("API key", text: $key)
                }
                TextField("Model", text: $modelName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !models.isEmpty {
                    Picker("Available models", selection: $modelName) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button(loading ? "Loading…" : "Load models") { loadModels() }.disabled(loading)
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Provider")
            } footer: {
                Text(provider.keyHelp + " Keys are stored in the Keychain on this phone.")
            }
        }
        .ambientList()
        .navigationTitle("Assistant")
        .onAppear(perform: loadFields)
        .onChange(of: providerRaw) { _, _ in models = []; status = nil; loadFields() }
        .onChange(of: url) { _, v in UserDefaults.standard.set(v, forKey: "assistantURL." + provider.rawValue) }
        .onChange(of: modelName) { _, v in UserDefaults.standard.set(v, forKey: "assistantModel." + provider.rawValue) }
        .onChange(of: key) { _, v in Keychain.set(v, for: provider.rawValue) }
    }

    private func loadFields() {
        let c = AssistantConfig.current
        url = c.baseURL
        modelName = c.model
        key = c.key ?? ""
    }

    private func loadModels() {
        loading = true
        status = nil
        Task {
            defer { loading = false }
            do {
                models = try await AssistantClient.models(config: AssistantConfig.current)
                status = models.isEmpty ? "The provider listed no models." : "\(models.count) models available."
                if !models.contains(modelName), let first = models.first { modelName = first }
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

/// Builds CSV and JSON files of the daily table and hands them to the share sheet. Files stay on the phone
/// until you send them somewhere.
struct ExportView: View {
    let model: DashboardModel
    @Query private var entries: [JournalEntry]
    @State private var days = 90
    @State private var files: (csv: URL, json: URL, rows: Int, columns: Int)?

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $days) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("All loaded").tag(0)
                }
                if let f = files {
                    ShareLink("Share CSV", item: f.csv)
                    ShareLink("Share JSON", item: f.json)
                    Text("\(f.rows) days, \(f.columns) columns").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } footer: {
                Text("One row per day: recovery, HRV, resting heart rate, sleep, strain, workouts, lifting volume, steps, food, body and journal tags. Morning and sleep columns describe the night that ended that morning. On a Mac, save it in the project's data folder, which git ignores.")
            }
        }
        .ambientList()
        .navigationTitle("Export data")
        .task(id: days) { build() }
    }

    private func build() {
        let today = Calendar.current.startOfDay(for: .now)
        let history = UserDefaults.standard.object(forKey: AppSettings.historyDaysKey) as? Int ?? AppSettings.defaultHistoryDays
        let n = days == 0 ? min(history, (model.snapshot.hrv.first.map { Calendar.current.dateComponents([.day], from: $0.date, to: today).day ?? 0 } ?? 0) + 1) : days
        let table = DailyExport.table(model.snapshot, recovery: model.recoveryHistory.isEmpty ? model.scoreHistory : model.recoveryHistory,
                                      training: model.training?.days ?? [], lifts: model.lifts,
                                      tags: entries.map { (day: $0.day, tags: $0.tags) },
                                      needHours: UserDefaults.standard.object(forKey: AppSettings.sleepNeedKey) as? Double ?? 8,
                                      days: max(n, 1), endingOn: today, feel: entries.feelSeries)
        let stamp = today.formatted(.iso8601.year().month().day())
        let dir = FileManager.default.temporaryDirectory
        let csv = dir.appendingPathComponent("health-daily-\(stamp).csv"), json = dir.appendingPathComponent("health-daily-\(stamp).json")
        do {
            try table.csv.write(to: csv, atomically: true, encoding: .utf8)
            try table.json.write(to: json, options: .atomic)
            files = (csv, json, table.rows.count, table.columns.count)
        } catch {
            files = nil
        }
    }
}
