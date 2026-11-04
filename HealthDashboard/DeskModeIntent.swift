import AppIntents
import HealthKit

/// Starts desk mode on the watch from the phone, for a Shortcuts automation. iOS can't tell when the watch is near
/// the Mac, so the trigger is up to the automation: a time of day, or a Focus shared from the Mac. Launching the
/// watch app with a workout configuration is the one way the phone can start a watch session in the background.
struct StartDeskModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start desk mode"
    static let description = IntentDescription("Starts desk mode on your Apple Watch, which taps you to stand up if you nod off at your desk.")

    @Parameter(title: "Only from 20:00", default: true)
    var eveningOnly: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let hour = Calendar.current.component(.hour, from: .now)
        if eveningOnly && !(hour >= 20 || hour < 4) {
            return .result(dialog: "Desk mode starts from 20:00.")
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        try await HKHealthStore().startWatchApp(toHandle: config)
        return .result(dialog: "Desk mode is on.")
    }
}

struct HealthShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDeskModeIntent(), phrases: ["Start desk mode in \(.applicationName)"],
                    shortTitle: "Desk mode", systemImageName: "figure.stand")
    }
}
