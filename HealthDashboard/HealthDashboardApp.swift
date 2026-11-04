import SwiftUI
import SwiftData

@main
struct HealthDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: JournalEntry.self)
    }
}

enum AppSettings {
    static let sleepNeedKey = "sleepNeedHours"
    static let proteinKey = "proteinTargetPerKg"
    static let historyDaysKey = "historyDays"
    static let weightGoalKey = "weightGoalKgPerWeek"
    static let goalWeightKey = "goalWeightKg"          // 0 means no goal
    static let wakeGoalKey = "wakeGoalMinutes"         // minutes after midnight
    static let defaultWakeGoal = 460.0                 // 07:40
    static let todayStyleKey = "todayStyle"            // "habits" (recovery with habits) or "balance"
    static let goalBodyFatKey = "goalBodyFatPercent"
    static let heightKey = "heightCm"                  // 0 means use Apple Health
    static let liftExerciseKey = "liftGoalExercise"
    static let liftGoalKey = "liftGoalKg"

    static let defaultProtein = 2.0
    static let defaultHistoryDays = 120
    /// Lean gain of about 0.25 kg per week.
    static let defaultWeightGoal = 0.25
    /// "All time" is 20 years: far enough back for any Apple Watch history, without enumerating empty decades.
    static let historyOptions: [(days: Int, label: String)] = [(120, "120 days"), (365, "1 year"), (730, "2 years"), (7300, "All time")]
}

struct RootView: View {
    @State private var model = DashboardModel()

    init() { WatchLink.shared.activate() }

    var body: some View {
        TabView {
            TodayView(model: model)
                .tabItem { Label("Today", systemImage: "heart.text.square") }
            TrendsView(model: model)
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            WorkoutsView(model: model)
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
            NavigationStack { NutritionDetailView(model: model) }
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            InfoView(model: model)
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .task { await model.refresh() }
        // Warm light design from the app icon: always light, rounded type, coral accent
        .preferredColorScheme(.light)
        .fontDesign(.rounded)
        .tint(Theme.accent)
    }
}

#Preview {
    RootView()
        .modelContainer(for: JournalEntry.self, inMemory: true)
}
