import SwiftUI
import Charts
import HealthCore

/// The latest Strong or Hevy export, kept as the raw file in Application Support. Both apps export the full
/// history every time, so a new import replaces the old file. Stays on device.
enum LiftStore {
    static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("lifts.csv")
    }
    /// Where imports went before Hevy was supported.
    static var legacyURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("strong.csv")
    }

    static func load() -> [LiftSession] {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: legacyURL, encoding: .utf8))
        else { return [] }
        return (try? LiftCSV.parse(text)) ?? []
    }

    /// Parses first, so a wrong file never replaces a good one.
    static func importFile(at source: URL) throws -> [LiftSession] {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: source, encoding: .utf8)
        let sessions = try LiftCSV.parse(text)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.removeItem(at: legacyURL)
        return sessions
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: legacyURL)
    }

    static func message(for error: Error) -> String {
        switch error as? StrongImportError {
        case .missingColumns(let c)?: "This doesn't look like a Strong or Hevy export. Missing: \(c.joined(separator: ", "))."
        case .noSets?: "No sets with reps found in this file."
        case nil: "Couldn't read the file: \(error.localizedDescription)"
        }
    }
}

private func kg(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(0...1))) + " kg"
}

private func setText(_ s: LiftSet) -> String {
    s.weight > 0 ? "\(s.weight.formatted(.number.precision(.fractionLength(0...2)))) × \(s.reps)" : "\(s.reps) reps"
}

struct StrengthCard: View {
    let model: DashboardModel

    var body: some View {
        Card(title: "Strength", systemImage: "dumbbell") {
            if model.lifts.isEmpty {
                Text("Import your Strong export in Settings to see volume and estimated maxes per exercise.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let weeks = model.liftWeeks
                if let last = weeks.last {
                    HStack {
                        MetricTile(label: "Volume this week", value: kg(last.volumeLoad), detail: "weight × reps")
                        MetricTile(label: "Working sets", value: "\(last.workingSets)", detail: "this week")
                    }
                }
                Chart(weeks) { w in
                    BarMark(x: .value("Week", w.weekStart, unit: .weekOfYear), y: .value("kg", w.volumeLoad / 1000))
                        .foregroundStyle(Palette.strain.gradient)
                }
                .chartYAxisLabel("tonnes per week")
                .frame(height: 140)
                Divider()
                ForEach(model.exercises.prefix(6)) { e in
                    NavigationLink {
                        ExerciseDetailView(exercise: e, sessions: model.lifts)
                    } label: {
                        ExerciseRow(exercise: e)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ExerciseRow: View {
    let exercise: ExerciseProgress

    var body: some View {
        HStack {
            Text(exercise.name).lineLimit(1)
            Spacer()
            if let c = exercise.current {
                Text(kg(c)).monospacedDigit()
            }
            Text(exercise.change.map { String(format: "%+.1f", $0) } ?? "")
                .monospacedDigit()
                .foregroundStyle((exercise.change ?? 0) >= 0 ? Palette.good : Palette.bad)
                .frame(width: 48, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .font(.subheadline)
    }
}

struct ExerciseDetailView: View {
    let exercise: ExerciseProgress
    let sessions: [LiftSession]

    private var recent: [(date: Date, sets: [LiftSet])] {
        sessions.compactMap { s in
            let sets = s.sets.filter { $0.exercise == exercise.name }
            return sets.isEmpty ? nil : (s.start, sets)
        }
        .prefix(10)
        .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "Estimated 1RM", systemImage: "chart.line.uptrend.xyaxis") {
                    HStack {
                        MetricTile(label: "Latest", value: exercise.current.map(kg) ?? "--")
                        MetricTile(label: "4 weeks", value: exercise.change.map { String(format: "%+.1f kg", $0) } ?? "--",
                                   detail: "change")
                        MetricTile(label: "Sessions", value: "\(exercise.sessions)", detail: "last 8 weeks")
                    }
                    LineTrend(points: exercise.e1rm, unit: "kg", color: Palette.strain)
                    Text("Best set of each session through the Epley formula, weight × (1 + reps / 30). Sets above 10 reps and warm-ups are left out.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Card(title: "Recent sessions", systemImage: "list.bullet") {
                    ForEach(recent, id: \.date) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                Spacer()
                                Text(kg(LiftingEngine.volumeLoad(r.sets))).foregroundStyle(.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            Text(r.sets.filter { !$0.isWarmup }.map(setText).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The logged sets for a watch workout, shown on its detail screen.
struct LiftSessionCard: View {
    let session: LiftSession

    var body: some View {
        Card(title: session.name.isEmpty ? "Sets" : session.name, systemImage: "dumbbell") {
            HStack {
                MetricTile(label: "Volume", value: kg(LiftingEngine.volumeLoad(session.sets)), detail: "weight × reps")
                MetricTile(label: "Working sets", value: "\(session.working.count)")
            }
            ForEach(session.exercises, id: \.self) { name in
                let sets = session.sets.filter { $0.exercise == name }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(name)
                        Spacer()
                        if let e = LiftingEngine.bestE1rm(sets) {
                            Text("e1RM " + kg(e)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    Text(sets.filter { !$0.isWarmup }.map(setText).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StrongImportSection: View {
    let model: DashboardModel
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        Section {
            Button("Import Strong or Hevy export") { picking = true }
            if !model.lifts.isEmpty {
                LabeledContent("Workouts", value: "\(model.lifts.count)")
                if let last = model.lifts.first {
                    LabeledContent("Latest", value: last.start.formatted(.dateTime.day().month().year()))
                }
                Button("Remove imported data", role: .destructive) {
                    LiftStore.remove()
                    model.reloadLifts()
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Strength log")
        } footer: {
            Text("In Strong: Settings, Export data. In Hevy: Profile, Settings, Export and import data. Save the CSV to Files and pick it here. Import again whenever you want to update.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let sessions = try LiftStore.importFile(at: result.get())
                message = "Imported \(sessions.count) workouts."
                model.reloadLifts()
            } catch {
                message = LiftStore.message(for: error)
            }
        }
    }
}
