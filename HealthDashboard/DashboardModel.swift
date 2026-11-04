import Foundation
import Observation
import HealthCore

@MainActor
@Observable
final class DashboardModel {
    var snapshot = HealthSnapshot()
    var recovery: RecoveryResult?
    var scoreHistory: [DailyValue] = []
    var sleep: SleepSummary?
    var load: LoadResult?
    var bodyComp: BodyResult?
    var nutrition: NutritionResult?
    var coach: CoachAdvice?
    var vitals: VitalsResult?
    var training: TrainingResult?
    var weekly: [ActivityLine] = []
    var tdeeHistory: [DailyValue] = []
    var lifts: [LiftSession] = []          // Strong log, newest first
    var exercises: [ExerciseProgress] = []
    var liftWeeks: [WeekVolume] = []
    var fetchSeconds: Double?
    /// Bumped after each refresh so views that recompute from the snapshot (Insights) know to run again.
    var refreshCount = 0
    var withingsConnected = WithingsService.isConnected
    var withingsMessage: String?
    /// Sleep, food and training habits against their research targets, for Today.
    var habits: [Habit] = []
    var readiness: ReadinessForecast?
    /// Recovery over the whole history setting (at most 2 years), for Trends. `scoreHistory` stays the last 90 days.
    var recoveryHistory: [DailyValue] = []
    var hrvReadiness: ReadinessForecast?
    var forecastPending = false
    var isLoading = false
    var errorMessage: String?

    private let service = HealthKitService()
    private var authorized = false

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard
        let historyDays = defaults.object(forKey: AppSettings.historyDaysKey) as? Int ?? AppSettings.defaultHistoryDays
        let started = Date.now
        guard var s = await loadSnapshot(days: historyDays) else { return }
        await addWithings(to: &s)
        s.room = RoomStore.load()
        #if DEBUG && targetEnvironment(simulator)
        if s.room.isEmpty { s.room = MockData.room(sleep: s.sleep) }
        #endif
        fetchSeconds = Date.now.timeIntervalSince(started)
        let today = Calendar.current.startOfDay(for: .now)
        let sleepNeed = defaults.object(forKey: AppSettings.sleepNeedKey) as? Double ?? 8
        let proteinTarget = defaults.object(forKey: AppSettings.proteinKey) as? Double ?? AppSettings.defaultProtein

        let recovery = RecoveryEngine.evaluate(s, day: today)
        let load = LoadEngine.evaluate(s, day: today)
        let nutrition = NutritionEngine.evaluate(s, day: today)

        snapshot = s
        self.recovery = recovery
        self.load = load
        self.nutrition = nutrition
        scoreHistory = RecoveryEngine.history(s, days: 90, endingOn: today)
        sleep = SleepEngine.summarize(s, day: today, needHours: sleepNeed)
        bodyComp = BodyEngine.evaluate(s, day: today)
        vitals = VitalsEngine.check(s, day: today)
        training = TrainingEngine.evaluate(s, day: today, recovery: recovery.score)
        weekly = ActivityEngine.weekly(s.workouts, endingOn: today)
        let weightGoal = defaults.object(forKey: AppSettings.weightGoalKey) as? Double ?? AppSettings.defaultWeightGoal
        habits = HabitEngine.evaluate(s, day: today, sleepScore: { SleepScoreEngine.score(s, night: $0, needHours: sleepNeed).score },
                                      training: training, recovery: scoreHistory, weightKg: bodyComp?.trendWeight,
                                      goalIntake: nutrition.suggestedIntake(kgPerWeek: weightGoal), proteinTarget: proteinTarget,
                                      wakeGoal: defaults.object(forKey: AppSettings.wakeGoalKey) as? Double ?? AppSettings.defaultWakeGoal)
        tdeeHistory = NutritionEngine.tdeeHistory(s, days: 90, endingOn: Calendar.current.date(byAdding: .day, value: -1, to: today)!)
        reloadLifts()
        coach = Coach.advise(recovery: recovery, load: load, nutrition: nutrition,
                             proteinTarget: proteinTarget, today: today)
        errorMessage = nil
        refreshCount += 1
        WidgetBridge.publish(self)
        Task { await fitForecast(s, load: load, today: today, historyDays: historyDays) }
    }

    /// The readiness model refits 30 times for its backtest, so it runs off the main thread after the cards are up.
    private func fitForecast(_ s: HealthSnapshot, load: LoadResult, today: Date, historyDays: Int) async {
        forecastPending = true
        defer { forecastPending = false }
        let plan = ReadinessEngine.plannedStrength(load, from: today, days: 5)
        let result = await Task.detached(priority: .utility) {
            // Only as far back as there is HRV, so "All time" doesn't score empty years.
            let cal = Calendar.current
            let span = s.hrv.first.map { (cal.dateComponents([.day], from: $0.date, to: today).day ?? 0) + 1 } ?? 0
            let days = min(historyDays, span, 730)
            let recovery = RecoveryEngine.history(s, days: days, endingOn: today)
            let burn = NutritionEngine.tdeeHistory(s, days: min(days, 365), endingOn: cal.date(byAdding: .day, value: -1, to: today)!)
            let hrv = s.hrv.map { DailyValue(date: $0.date, value: 100 * log($0.value)) }   // log scale: changes read as %
            return (recovery, burn,
                    ReadinessEngine.evaluate(recovery.recent(days: 365, from: today), workouts: s.workouts, name: "Recovery",
                                             effectSD: 10, plan: plan, today: today),
                    ReadinessEngine.evaluate(hrv, workouts: s.workouts, name: "HRV", effectSD: 10, plan: plan, today: today))
        }.value
        recoveryHistory = result.0
        if !result.1.isEmpty { tdeeHistory = result.1 }
        readiness = result.2
        hrvReadiness = result.3
    }

    /// Reads the imported Strong log. Debug builds on the Simulator get a mock log when nothing is imported.
    func reloadLifts() {
        let today = Calendar.current.startOfDay(for: .now)
        lifts = LiftStore.load()
        #if DEBUG && targetEnvironment(simulator)
        if lifts.isEmpty { lifts = MockData.lifts(matching: snapshot.workouts) }
        #endif
        exercises = LiftingEngine.progress(lifts, endingOn: today)
        liftWeeks = LiftingEngine.weekly(lifts, weeks: 12, endingOn: today)
    }

    /// Body composition Apple Health can't store. A failed sync keeps the last cached weigh-ins.
    private func addWithings(to s: inout HealthSnapshot) async {
        withingsConnected = WithingsService.isConnected
        guard withingsConnected else { return }
        do {
            WithingsBody.apply(try await WithingsService.sync().groups, to: &s)
            withingsMessage = nil
        } catch {
            WithingsBody.apply(WithingsService.cached().groups, to: &s)
            withingsMessage = error.localizedDescription
        }
        withingsConnected = WithingsService.isConnected
    }

    func lift(for workout: WorkoutSummary) -> LiftSession? {
        LiftingEngine.session(for: workout, in: lifts)
    }

    func sleepScore(for night: SleepNight) -> SleepScore {
        let need = UserDefaults.standard.object(forKey: AppSettings.sleepNeedKey) as? Double ?? 8
        return SleepScoreEngine.score(snapshot, night: night, needHours: need)
    }

    /// Real Health data on a device. The Simulator has no Health data, so debug builds there use mock data.
    private func loadSnapshot(days: Int) async -> HealthSnapshot? {
        #if DEBUG && targetEnvironment(simulator)
        return MockData.snapshot(days: min(days, 365))
        #else
        guard HealthKitService.isAvailable else {
            errorMessage = "Apple Health isn't available on this device."
            return nil
        }
        if !authorized {
            do {
                try await service.requestAuthorization()
                authorized = true
            } catch {
                errorMessage = "Health access failed: \(error.localizedDescription)"
                return nil
            }
        }
        return await service.fetchSnapshot(days: days)
        #endif
    }
}
