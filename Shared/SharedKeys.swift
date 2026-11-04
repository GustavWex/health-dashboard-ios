import Foundation

/// Keys shared by the app, its widgets and the watch through App Group containers and WatchConnectivity.
enum SharedKeys {
    static let group = "group.dk.gustavwex.HealthDashboard"
    static let widgetKind = "RecoveryWidget"
    static let score = "recoveryScore"
    static let zone = "recoveryZone"
    static let date = "recoveryDate"
    // The day as the watch shows it
    static let status = "dayStatus"            // 0 take it easy, 1 steady, 2 good
    static let sleep = "sleepScore"
    static let strain = "strain"
    static let strainLow = "strainTargetLow"
    static let strainHigh = "strainTargetHigh"
    static let wakeGoal = "wakeGoalMinutes"
    /// When the wake goal was last set on the watch, so an older context from the phone doesn't undo it.
    static let wakeGoalSetAt = "wakeGoalSetAt"
    static let dayKind = "DayComplication"
    static let sleepKind = "SleepComplication"
    static let strainKind = "StrainComplication"

    static let all = [score, zone, date, status, sleep, strain, strainLow, strainHigh, wakeGoal]
}
