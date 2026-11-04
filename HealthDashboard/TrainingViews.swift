import SwiftUI
import Charts
import HealthCore

private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]
private let zoneNames = ["Zone 1, 50 to 60%", "Zone 2, 60 to 70%", "Zone 3, 70 to 80%", "Zone 4, 80 to 90%", "Zone 5, 90%+"]

struct WorkoutRow: View {
    let workout: WorkoutSummary
    let tau: Double?

    var body: some View {
        HStack {
            Text(workout.name)
            Spacer()
            if let s = strain(workout, tau) {
                Text(fmt(s, 1)).monospacedDigit().foregroundStyle(Palette.strain)
            }
            Text("\(Int(workout.duration / 60)) min").foregroundStyle(.secondary)
            Text(workout.start.formatted(.dateTime.weekday(.abbreviated).day()))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .font(.subheadline)
    }
}

private func strain(_ w: WorkoutSummary, _ tau: Double?) -> Double? {
    guard let t = w.heartRate?.trimp, let tau else { return nil }
    return TrainingEngine.strain(trimp: t, tau: tau)
}

struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    let tau: Double?
    var lift: LiftSession? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: workout.name, systemImage: "figure.strengthtraining.traditional") {
                    Text(workout.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                        .foregroundStyle(.secondary)
                    HStack {
                        MetricTile(label: "Strain", value: fmt(strain(workout, tau), 1), detail: "of 21")
                        MetricTile(label: "Duration", value: "\(Int(workout.duration / 60)) min")
                        MetricTile(label: "Energy", value: fmt(workout.energy, 0, " kcal"))
                    }
                    HStack {
                        MetricTile(label: "Effort", value: fmt(workout.effort, 0, " / 10"),
                                   detail: workout.effort == nil ? "rate it on your watch" : (workout.effortIsEstimate ? "watch estimate" : "your rating"))
                        MetricTile(label: "Effort load", value: workout.effort == nil ? "--" : fmt(TrainingEngine.srpe(workout), 0),
                                   detail: "effort × minutes")
                        MetricTile(label: "HR recovery", value: fmt(workout.hrRecovery, 0, " bpm"), detail: "first minute")
                    }
                }

                if let lift {
                    LiftSessionCard(session: lift)
                }

                if let hr = workout.heartRate {
                    Card(title: "Heart rate", systemImage: "heart") {
                        HStack {
                            MetricTile(label: "Average", value: fmt(hr.average, 0, " bpm"))
                            MetricTile(label: "Max", value: fmt(hr.max, 0, " bpm"))
                            MetricTile(label: "TRIMP", value: fmt(hr.trimp, 0))
                        }
                    }
                    Card(title: "Zones", systemImage: "chart.bar.fill") {
                        ForEach(0..<5, id: \.self) { i in
                            HStack {
                                Circle().fill(zoneColors[i]).frame(width: 8, height: 8)
                                Text(zoneNames[i]).font(.subheadline)
                                Spacer()
                                Text("\(Int(hr.zoneMinutes[i].rounded())) min").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Text("Percent of heart rate reserve, between your resting and maximum heart rate.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Card(title: "Heart rate", systemImage: "heart") {
                        Text("No heart rate recorded for this workout.").foregroundStyle(.secondary)
                    }
                }

                Card(title: "How strain works", systemImage: "info.circle") {
                    Text("Strain comes from heart rate: every minute counts more the closer you are to your max (Banister TRIMP). It is scaled 0 to 21 so your usual training day lands at 10.5. Heart rate undercounts heavy lifting, so for strength sessions the effort load from your watch rating is the fairer number.")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WeeklySummary: View {
    let lines: [ActivityLine]

    var body: some View {
        if lines.isEmpty {
            Text("No workouts in the last 5 weeks.").foregroundStyle(.secondary)
        } else {
            HStack {
                Text("Last 7 days").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("usual week").font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
            }
            ForEach(lines) { l in
                HStack {
                    Text(l.name)
                    Spacer()
                    Text("\(l.count)× · \(Int(l.minutes)) min").monospacedDigit()
                    Text(fmt(l.usualCount, 1) + "× · \(Int(l.usualMinutes)) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                }
                .font(.subheadline)
            }
            let total = lines.reduce(0) { $0 + $1.minutes }, usual = lines.reduce(0) { $0 + $1.usualMinutes }
            Divider()
            LabeledContent("Total", value: "\(Int(total)) min vs \(Int(usual)) min usual")
                .font(.subheadline.weight(.semibold))
        }
    }
}
