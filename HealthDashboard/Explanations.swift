import SwiftUI
import HealthCore

// Explanation cards in one pattern: what the number says, what drove it, what to do, and its assumptions.

/// Why today's strain is what it is: each workout's share of today's heart rate load.
struct StrainExplanation: View {
    let model: DashboardModel

    private var today: [WorkoutSummary] {
        model.snapshot.workouts.filter { Calendar.current.isDateInToday($0.start) }
    }

    var body: some View {
        let t = model.training
        let total = today.compactMap { $0.heartRate?.trimp }.reduce(0, +)
        Card(title: "Why this strain", systemImage: "flame") {
            if total > 0 {
                ForEach(today) { w in
                    if let trimp = w.heartRate?.trimp {
                        HStack {
                            Text(w.name)
                            Text("\(Int(w.duration / 60)) min").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((100 * trimp / total).rounded()))% of today's load").monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            } else {
                Text("No workout with heart rate yet today, so strain is 0.").font(.subheadline)
            }
            if let s = t?.today?.strain, let target = t?.strainTarget {
                Divider()
                Label(advice(s, target), systemImage: "target").font(.subheadline)
            }
        }
    }

    private func advice(_ s: Double, _ target: ClosedRange<Double>) -> String {
        if s < target.lowerBound { return String(format: "%.1f below today's target, so there is room for a session.", target.lowerBound - s) }
        if s > target.upperBound { return "Above today's target. Keep the rest of the day easy." }
        return "Inside today's target."
    }
}

/// Why the forecast says what it says: carry-over from this morning and the planned session.
struct ForecastExplanation: View {
    let model: DashboardModel

    var body: some View {
        if let f = model.readiness, let first = f.days.first, let today = model.recovery?.score {
            let carry = f.model.phi * (today - f.model.mu)
            Card(title: "Why \(first.date.formatted(.dateTime.weekday(.wide))) looks like this", systemImage: "arrow.right.circle") {
                Label(String(format: "This morning is %.0f against your average %.0f. About %.0f%% of a gap carries into the next morning, so %+.0f.",
                             today, f.model.mu, 100 * max(0, f.model.phi), carry),
                      systemImage: "arrow.uturn.right")
                if first.strengthPlanned {
                    Label(String(format: "Your rhythm puts a strength session the day before: %+.0f against resting.", first.planned - first.rest),
                          systemImage: "dumbbell")
                } else {
                    Label("No strength session planned the day before.", systemImage: "bed.double")
                }
            }
            .font(.subheadline)
        }
    }
}

/// What the person could try, phrased as a small experiment rather than an instruction.
enum InsightAction {
    static func suggestion(_ i: Insight) -> String {
        let moreIsGood = (i.r > 0) == i.outcome.higherIsBetter
        let name = i.feature.name.inSentence
        if i.feature.kind == .flag {
            return moreIsGood
                ? "Your data suggests days with \(name) help. If it fits your week, keep them and watch whether \(i.outcome.name.inSentence) follows."
                : "Try a couple of weeks with fewer \(name) days and see whether \(i.outcome.name.inSentence) improves."
        }
        let t = InsightText.value(i.threshold ?? 0, i.feature.kind)
        let side = i.feature.kind == .clock ? (moreIsGood ? "after \(t)" : "before \(t)") : (moreIsGood ? "above \(t)" : "under \(t)")
        return "Try keeping \(name) \(side) for two weeks and see whether \(i.outcome.name.inSentence) follows."
    }

}
