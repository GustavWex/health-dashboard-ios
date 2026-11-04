import SwiftUI
import Charts
import HealthCore

/// The metrics shown in Trends, each with its unit, precision and better direction.
enum TrendMetric: String, CaseIterable, Identifiable {
    case recovery, hrv, restingHR, sleep, strain, weight, leanMass, muscleMass, visceralFat, intake, protein, burn, steps, activeEnergy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .recovery: "Recovery"
        case .hrv: "HRV"
        case .restingHR: "Resting HR"
        case .sleep: "Sleep"
        case .strain: "Day strain"
        case .weight: "Weight"
        case .leanMass: "Lean mass"
        case .muscleMass: "Muscle mass"
        case .visceralFat: "Visceral fat"
        case .intake: "Calories"
        case .burn: "Energy burn"
        case .protein: "Protein"
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        }
    }

    var unit: String {
        switch self {
        case .recovery, .strain, .steps, .visceralFat: ""
        case .hrv: "ms"
        case .restingHR: "bpm"
        case .sleep: "h"
        case .weight, .leanMass, .muscleMass: "kg"
        case .intake, .activeEnergy, .burn: "kcal"
        case .protein: "g"
        }
    }

    var digits: Int {
        switch self {
        case .sleep, .strain, .weight, .leanMass, .muscleMass: 1
        default: 0
        }
    }

    @MainActor
    func values(_ m: DashboardModel) -> [DailyValue] {
        let s = m.snapshot
        let logged = Set(s.dietaryEnergy.filter { $0.value > 300 }.map(\.date))
        switch self {
        case .recovery: return m.recoveryHistory.isEmpty ? m.scoreHistory : m.recoveryHistory
        case .hrv: return s.hrv
        case .restingHR: return s.restingHR
        case .sleep: return s.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) }
        case .strain: return (m.training?.days ?? []).compactMap { d in d.strain.map { DailyValue(date: d.date, value: $0) } }
        case .weight: return s.weight
        case .leanMass: return s.leanMass
        case .muscleMass: return s.muscleMass
        case .visceralFat: return s.visceralFat
        case .intake: return s.dietaryEnergy.filter { logged.contains($0.date) }
        case .protein: return s.protein.filter { logged.contains($0.date) }
        case .steps: return s.steps
        case .activeEnergy: return s.activeEnergy
        case .burn: return m.tdeeHistory
        }
    }

    var color: Color {
        switch self {
        case .recovery, .hrv, .restingHR: Palette.heart
        case .sleep: Palette.sleep
        case .strain, .steps, .activeEnergy: Palette.strain
        case .weight, .leanMass, .muscleMass, .visceralFat: Palette.body
        case .intake, .protein, .burn: Palette.nutrition
        }
    }

    /// Recommended order for Today: accurate readings that say most about recovery and lean gain first.
    /// Wrist heart rate is accurate at rest while wrist energy estimates are not (Shcherbina et al. 2017,
    /// "Accuracy in wrist-worn, sensor-based measurements of heart rate and energy expenditure", J Pers Med 7(2)).
    static let recommended: [TrendMetric] = [.hrv, .restingHR, .sleep, .weight, .recovery, .muscleMass, .protein,
                                             .strain, .leanMass, .intake, .steps, .visceralFat, .burn, .activeEnergy]
    static let defaultToday: [TrendMetric] = [.hrv, .restingHR, .sleep, .weight]

    var why: String {
        switch self {
        case .hrv: "Most sensitive sign of recovery; read at rest overnight, where the watch is reliable."
        case .restingHR: "One of the watch's most accurate readings. Rises with fatigue, illness and late meals."
        case .sleep: "Total sleep from the watch is reliable, and short nights show up everywhere else."
        case .weight: "The scale is precise, and the trend removes daily water swings. Tracks your gain rate."
        case .recovery: "Sums up HRV, resting HR, breathing and sleep against your own normal."
        case .muscleMass: "Speaks directly to lean gain. Noisy day to day, so read the trend."
        case .protein: "Drives muscle gain. As accurate as your logging."
        case .strain: "Your training load from heart rate. Undercounts heavy lifting."
        case .leanMass: "Lean gain from the scale. Overlaps with muscle mass."
        case .intake: "As accurate as your logging; gaps make it look low."
        case .steps: "Accurate count, but says little about lifting."
        case .visceralFat: "A scale estimate that moves slowly."
        case .burn: "An estimate built from intake and weight change."
        case .activeEnergy: "Wrist calorie estimates can be far off, so treat it as a rough guide."
        }
    }

    /// Body measures and the burn estimate are levels: the latest value says more than a 7-day mean.
    var isLevel: Bool { [.weight, .leanMass, .muscleMass, .visceralFat, .burn].contains(self) }

    /// Whether up is good, for colouring changes. nil when it depends on your goal.
    var higherIsBetter: Bool? {
        switch self {
        case .recovery, .hrv, .sleep, .leanMass, .muscleMass, .protein, .steps: true
        case .restingHR, .visceralFat: false
        default: nil
        }
    }

    func format(_ v: Double?) -> String {
        fmt(v, digits, unit.isEmpty ? "" : " " + unit)
    }
}

/// The last 12 weeks side by side, with the change from the week before.
struct WeekByWeekView: View {
    let model: DashboardModel
    let metrics: [TrendMetric]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(metrics) { m in
                    Card(title: m.name, systemImage: "calendar") {
                        let weeks = Array(Weekly.means(m.values(model)).suffix(12))
                        if weeks.isEmpty {
                            Text("No data yet.").foregroundStyle(.secondary)
                        } else {
                            Chart(weeks) { w in
                                BarMark(x: .value("Week", w.date, unit: .weekOfYear), y: .value(m.name, w.value))
                                    .foregroundStyle(Color.accentColor.gradient)
                            }
                            .chartYScale(domain: .automatic(includesZero: m == .recovery || m == .strain))
                            .frame(height: 140)
                            ForEach(Array(weeks.enumerated().reversed()), id: \.offset) { i, w in
                                HStack {
                                    Text("Week of " + w.date.formatted(.dateTime.day().month()))
                                    Spacer()
                                    Text(m.format(w.value)).monospacedDigit()
                                    Text(i > 0 ? String(format: "%+.\(m.digits)f", w.value - weeks[i - 1].value) : "")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                Text("Weeks run Monday to Sunday; the current week is partial.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Week by week")
        .navigationBarTitleDisplayMode(.inline)
    }
}
