import SwiftUI
import HealthCore

enum GoalText {
    /// "Goal 70.0 kg: 5.0 kg to go, about 20 weeks at your current rate."
    static func weight(trend: Double, goal: Double, ratePerWeek: Double?) -> String {
        let gap = goal - trend
        if abs(gap) < 0.3 { return String(format: "Goal %.1f kg: you're there.", goal) }
        var s = String(format: "Goal %.1f kg: %.1f kg to %@", goal, abs(gap), gap > 0 ? "gain" : "lose")
        if let r = ratePerWeek, let weeks = Goals.timeToGoal(current: trend, goal: goal, rate: r) {
            s += ", about \(Int(weeks.rounded())) weeks at your current rate."
        } else {
            s += ". Your current trend is moving the other way."
        }
        return s
    }
}

/// Goal weight, the weight a body fat target implies, a height-based muscular ceiling, and a lifting goal.
struct GoalsView: View {
    let model: DashboardModel
    @AppStorage(AppSettings.goalWeightKey) private var goalWeight = 0.0
    @AppStorage(AppSettings.goalBodyFatKey) private var goalFat = 12.0
    @AppStorage(AppSettings.heightKey) private var heightCm = 0.0
    @AppStorage(AppSettings.liftExerciseKey) private var liftExercise = ""
    @AppStorage(AppSettings.liftGoalKey) private var liftGoal = 80.0

    private var body_: BodyResult? { model.bodyComp }
    private var height: Double? { heightCm > 0 ? heightCm / 100 : model.snapshot.profile.height }
    private var exercise: ExerciseProgress? {
        model.exercises.first { $0.name == liftExercise }
            ?? model.exercises.first { $0.name.localizedCaseInsensitiveContains("bench") }
            ?? model.exercises.first
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Height") {
                    TextField("cm", value: $heightCm, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            } footer: {
                Text(heightCm > 0 ? "Using your own height. Set 0 to use Apple Health." :
                        (model.snapshot.profile.height.map { String(format: "From Apple Health: %.0f cm.", $0 * 100) } ?? "Not in Apple Health; type it here."))
            }

            Section("Goal weight") {
                Stepper(goalWeight > 0 ? String(format: "%.1f kg", goalWeight) : "No goal", value: $goalWeight, in: 0...150, step: 0.5)
                if goalWeight > 0, let t = body_?.trendWeight {
                    Text(GoalText.weight(trend: t, goal: goalWeight, ratePerWeek: body_?.ratePerWeek)).font(.subheadline)
                }
                if goalWeight == 0, let t = body_?.trendWeight {
                    Button(String(format: "Start from your trend weight, %.1f kg", t)) { goalWeight = (t * 2).rounded() / 2 }
                }
            }

            Section {
                Stepper(String(format: "Goal body fat %.0f%%", goalFat), value: $goalFat, in: 5...30, step: 1)
                if let lean = body_?.leanMass, let w = Goals.weight(lean: lean, bodyFat: goalFat / 100) {
                    LabeledContent("With today's lean mass", value: String(format: "%.1f kg", w))
                    Button("Use as goal weight") { goalWeight = (w * 2).rounded() / 2 }
                } else {
                    Text("Needs a weigh-in with body fat from your scale.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Body fat goal")
            } footer: {
                Text("Weight = lean mass ÷ (1 − body fat). Holds your lean mass where it is today; gaining muscle moves it up.")
            }

            Section {
                if let h = height, let lean = body_?.leanMass, let f = Goals.ffmi(lean: lean, height: h) {
                    LabeledContent("Your FFMI now", value: String(format: "%.1f", f.normalized))
                    if let maxLean = Goals.lean(normalizedFFMI: Goals.naturalFFMI, height: h) {
                        LabeledContent("Lean mass at FFMI 25", value: String(format: "%.0f kg", maxLean))
                        if let w = Goals.weight(lean: maxLean, bodyFat: goalFat / 100) {
                            LabeledContent(String(format: "That at %.0f%% body fat", goalFat), value: String(format: "%.0f kg", w))
                        }
                        Text(String(format: "Room to add about %.0f kg of lean mass before the drug-free ceiling.", max(0, maxLean - lean)))
                            .font(.subheadline)
                    }
                } else {
                    Text("Needs your height and a weigh-in with body fat.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Muscle ceiling for your height")
            } footer: {
                Text("Fat-free mass index is lean mass ÷ height², adjusted to 1.8 m. Drug-free lifters rarely pass about 25 (Kouri et al. 1995). Most people stop well before it; it's an upper bound, not a target.")
            }

            Section {
                if model.exercises.isEmpty {
                    Text("Import your Strong log in Settings to set a lifting goal.").foregroundStyle(.secondary)
                } else {
                    Picker("Exercise", selection: Binding(get: { exercise?.name ?? "" }, set: { liftExercise = $0 })) {
                        ForEach(model.exercises) { Text($0.name).tag($0.name) }
                    }
                    Stepper(String(format: "Goal %.1f kg", liftGoal), value: $liftGoal, in: 10...300, step: 2.5)
                    if let e = exercise, let current = e.current {
                        LabeledContent("Estimated max now", value: String(format: "%.1f kg", current))
                        if let rate = e.change, let months = Goals.timeToGoal(current: current, goal: liftGoal, rate: rate) {
                            LabeledContent("At your 4-week rate", value: months < 0.5 ? "there" : "about \(Int(months.rounded())) months")
                        } else if current < liftGoal {
                            LabeledContent("At your 4-week rate", value: "no recent progress")
                        }
                        if let bw = body_?.trendWeight, let w = Goals.weight(forLift: liftGoal, current: current, bodyWeight: bw), current < liftGoal {
                            Text(String(format: "At your current strength for your size, %.1f kg would come at about %.0f kg body weight. Getting stronger per kg gets you there lighter.", liftGoal, w))
                                .font(.subheadline)
                        }
                    }
                }
            } header: {
                Text("Lifting goal")
            } footer: {
                Text("Estimated max is the Epley formula on your best set. The body weight line assumes strength grows with body mass to the power 2/3 (Jaric 2002), so it is a rough guide, not a prediction.")
            }
        }
        .ambientList()
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}
