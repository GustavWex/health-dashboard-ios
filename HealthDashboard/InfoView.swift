import SwiftUI
import SwiftData
import HealthCore

/// Information: the journal, body composition and the raw data behind every score, newest first.
struct InfoView: View {
    let model: DashboardModel
    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]

    private var s: HealthSnapshot { model.snapshot }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { JournalView(model: model) } label: {
                        row("Journal", "book.closed", Palette.heart, journalDetail)
                    }
                    NavigationLink { GoalsView(model: model) } label: {
                        row("Goals", "flag.checkered", Palette.body, goalDetail)
                    }
                    NavigationLink { BedroomView(model: model) } label: {
                        row("Bedroom", "wind", Palette.air, s.room.isEmpty ? "CO2, temperature, humidity and light" : "\(RoomEngine.nights(s.room, sleep: s.sleep).count) nights measured")
                    }
                    NavigationLink { DetailPage(title: "Body") { BodyCard(model: model) } } label: {
                        row("Body", "scalemass", Palette.body, model.bodyComp?.trendWeight.map { String(format: "Trend weight %.1f kg", $0) } ?? "No weigh-ins yet")
                    }
                }
                Section {
                    NavigationLink { RawList(title: "Nights", rows: nights) } label: {
                        row("Nights", "bed.double", Palette.sleep, "\(s.sleep.count) nights")
                    }
                    NavigationLink { RawList(title: "Overnight readings", rows: overnight) } label: {
                        row("Overnight readings", "waveform.path.ecg", Palette.heart, "HRV, resting HR, breathing, temperature")
                    }
                    NavigationLink { RawList(title: "Workouts", rows: workouts) } label: {
                        row("Workouts", "figure.strengthtraining.traditional", Palette.strain, "\(s.workouts.count) workouts")
                    }
                    NavigationLink { RawList(title: "Weigh-ins", rows: weighIns) } label: {
                        row("Weigh-ins", "scalemass", Palette.body, "\(s.weight.count) weigh-ins")
                    }
                    NavigationLink { RawList(title: "Alarms, naps and desk mode", rows: watchSessions) } label: {
                        row("Alarms, naps and desk mode", "alarm", Palette.sleep, "\(WatchSessionLog.load().count) sessions from the watch")
                    }
                    NavigationLink { RawList(title: "Food", rows: food) } label: {
                        row("Food", "fork.knife", Palette.nutrition, "\(s.dietaryEnergy.filter { $0.value > 300 }.count) logged days")
                    }
                } header: {
                    Text("Raw data")
                } footer: {
                    Text("Straight from Apple Health, Withings and Strong, before any scoring. Newest first.")
                }
            }
            .ambientList()
            .navigationTitle("Info")
        }
    }

    private func row(_ title: String, _ icon: String, _ color: Color, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var goalDetail: String {
        let goal = UserDefaults.standard.double(forKey: AppSettings.goalWeightKey)
        return goal > 0 ? String(format: "Goal weight %.1f kg", goal) : "Weight, body fat and lifting goals"
    }

    private var journalDetail: String {
        guard let last = entries.first(where: { !$0.tags.isEmpty }) else { return "Tag what happened on a day" }
        return "Last tagged " + last.day.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    // MARK: Raw rows

    private func day(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).day().month()) }
    private func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    private var nights: [RawRow] {
        s.sleep.reversed().map { n in
            RawRow(id: "n\(n.date.timeIntervalSince1970)", title: day(n.date),
                   value: String(format: "%.1f h", n.asleep / 3600),
                   detail: "\(time(n.start)) to \(time(n.end)), \(n.awakenings) awakenings, \(Int(n.waso / 60)) min awake")
        }
    }

    private var overnight: [RawRow] {
        s.hrv.reversed().map { h in
            let parts = [fmt(s.restingHR.value(on: h.date), 0, " bpm"), fmt(s.respiratoryRate.value(on: h.date), 1, " /min"),
                         s.wristTemp.value(on: h.date).map { String(format: "%.2f °C", $0) } ?? "--"]
            return RawRow(id: "o\(h.date.timeIntervalSince1970)", title: day(h.date), value: fmt(h.value, 0, " ms"),
                          detail: "Resting HR " + parts[0] + ", breathing " + parts[1] + ", wrist " + parts[2])
        }
    }

    private var workouts: [RawRow] {
        s.workouts.map { w in
            RawRow(id: w.id.uuidString, title: w.name + ", " + day(w.start), value: "\(Int(w.duration / 60)) min",
                   detail: [w.heartRate.map { "avg \(Int($0.average)) bpm, TRIMP \(Int($0.trimp))" },
                            w.energy.map { "\(Int($0)) kcal" }, w.effort.map { "effort \(Int($0))/10" }]
                       .compactMap { $0 }.joined(separator: ", "))
        }
    }

    private var weighIns: [RawRow] {
        s.weight.reversed().map { w in
            RawRow(id: "w\(w.date.timeIntervalSince1970)", title: day(w.date), value: String(format: "%.1f kg", w.value),
                   detail: [s.bodyFat.value(on: w.date).map { String(format: "fat %.1f%%", $0 * 100) },
                            s.leanMass.value(on: w.date).map { String(format: "lean %.1f kg", $0) },
                            s.muscleMass.value(on: w.date).map { String(format: "muscle %.1f kg", $0) }]
                       .compactMap { $0 }.joined(separator: ", "))
        }
    }

    private var watchSessions: [RawRow] {
        WatchSessionLog.load().map { e in
            RawRow(id: "s\(e.start.timeIntervalSince1970)", title: e.kind.capitalized + ", " + day(e.start) + " " + time(e.start),
                   value: "\(Int(e.end.timeIntervalSince(e.start) / 60)) min",
                   detail: "\(e.reason), \(e.epochs) epochs, peak movement \(String(format: "%.3f", e.peakActivity)) g")
        }
    }

    private var food: [RawRow] {
        s.dietaryEnergy.filter { $0.value > 300 }.reversed().map { f in
            RawRow(id: "f\(f.date.timeIntervalSince1970)", title: day(f.date), value: "\(Int(f.value)) kcal",
                   detail: ["protein " + fmt(s.protein.value(on: f.date), 0, " g"), "fat " + fmt(s.fat.value(on: f.date), 0, " g"),
                            "carbs " + fmt(s.carbs.value(on: f.date), 0, " g")].joined(separator: ", "))
        }
    }
}

struct RawRow: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

struct RawList: View {
    let title: String
    let rows: [RawRow]

    var body: some View {
        List(rows) { r in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(r.title)
                    Spacer()
                    Text(r.value).monospacedDigit().fontWeight(.semibold)
                }
                if !r.detail.isEmpty {
                    Text(r.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if rows.isEmpty { Text("Nothing recorded yet").foregroundStyle(.secondary) } }
        .ambientList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
