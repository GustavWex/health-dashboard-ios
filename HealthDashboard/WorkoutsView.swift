import SwiftUI
import HealthCore

/// Everything about training in one tab: today's strain and load, the strain trend, this week, strength
/// progress from Strong, how a session moves your next mornings, and every workout.
struct WorkoutsView: View {
    let model: DashboardModel
    @State private var filter = Filter.all
    @State private var showAll = false

    enum Filter: String, CaseIterable {
        case all = "All", strength = "Strength", other = "Other"
    }

    private var workouts: [WorkoutSummary] {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        return model.snapshot.workouts.filter { w in
            w.start >= since && (filter == .all || (filter == .strength) == w.isStrength)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TrainingCard(model: model, showRecent: false)
                    Card(title: "Day strain, 28 days", systemImage: "flame.fill") {
                        BarTrend(points: TrendRange.month.shown((model.training?.days ?? []).compactMap { d in
                                     d.strain.map { DailyValue(date: d.date, value: $0) } }).suffix(28).map { $0 },
                                 unit: "strain", color: Palette.strain)
                    }
                    Card(title: "This week", systemImage: "calendar") {
                        WeeklySummary(lines: model.weekly)
                    }
                    StrengthCard(model: model)
                    RecoveryCurveCard(model: model)
                    workoutList
                    NavigationLink { GoalsView(model: model) } label: {
                        HStack {
                            Label("Lifting goal", systemImage: "flag.checkered")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                        .padding()
                        .glassCard(16)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(AmbientBackground())
            .navigationTitle("Workouts")
            .refreshable { await model.refresh() }
        }
    }

    private var workoutList: some View {
        Card(title: "Workouts, 90 days", systemImage: "list.bullet") {
            Picker("Type", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            if workouts.isEmpty {
                Text("No workouts in Apple Health yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            let shown = showAll ? workouts : Array(workouts.prefix(12))
            ForEach(shown) { w in
                NavigationLink {
                    WorkoutDetailView(workout: w, tau: model.training?.tau, lift: model.lift(for: w))
                } label: {
                    WorkoutRow(workout: w, tau: model.training?.tau)
                }
                .buttonStyle(.plain)
                if w.id != shown.last?.id { Divider() }
            }
            if workouts.count > 12 {
                Button(showAll ? "Show fewer" : "Show all \(workouts.count)") { withAnimation { showAll.toggle() } }
                    .font(.subheadline)
            }
        }
    }
}
