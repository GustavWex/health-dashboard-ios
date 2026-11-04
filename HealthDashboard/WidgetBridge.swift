import Foundation
import WidgetKit
import WatchConnectivity
import HealthCore

/// Hands today's numbers to the home screen widget (App Group) and to the watch (WatchConnectivity). Only the
/// scores leave the app's own container: into the App Group on this phone and to your own paired watch.
@MainActor
enum WidgetBridge {
    static func publish(_ m: DashboardModel) {
        var payload: [String: Any] = [SharedKeys.date: Date.now.timeIntervalSince1970]
        payload[SharedKeys.score] = m.recovery?.score
        payload[SharedKeys.zone] = m.recovery?.zone?.rawValue
        payload[SharedKeys.status] = m.dayStatus?.rawValue
        payload[SharedKeys.sleep] = m.sleep.flatMap { $0.lastNight ?? $0.latestNight }.map { m.sleepScore(for: $0).score }
        payload[SharedKeys.strain] = m.training?.today?.strain ?? (m.training?.tau == nil ? nil : 0)
        payload[SharedKeys.strainLow] = m.training?.strainTarget?.lowerBound
        payload[SharedKeys.strainHigh] = m.training?.strainTarget?.upperBound
        payload[SharedKeys.wakeGoal] = UserDefaults.standard.object(forKey: AppSettings.wakeGoalKey) as? Double ?? AppSettings.defaultWakeGoal
        if let d = UserDefaults(suiteName: SharedKeys.group) {
            for k in SharedKeys.all { d.set(payload[k] ?? nil, forKey: k) }
            d.set(Date.now, forKey: SharedKeys.date)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: SharedKeys.widgetKind)
        WatchLink.shared.send(payload)
    }
}

/// The phone side of WatchConnectivity. Application context keeps the latest numbers for the watch app; when a
/// complication is on the watch face, a complication transfer also wakes the watch to redraw it (iOS limits these
/// to a daily budget, so the context is the fallback).
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchLink()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(payload)
        if s.isComplicationEnabled, s.remainingComplicationUserInfoTransfers > 0 {
            s.transferCurrentComplicationUserInfo(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    /// Alarm, nap and desk mode summaries from the watch, kept for tuning (see `WatchSessionLog`), and a wake
    /// time set on the watch, which becomes the app's wake goal.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["sessionLog"] as? Data { WatchSessionLog.append(data) }
        if let wake = userInfo[SharedKeys.wakeGoal] as? Double {
            DispatchQueue.main.async { UserDefaults.standard.set(wake, forKey: AppSettings.wakeGoalKey) }
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}

/// The watch's session summaries, stored as JSON on the phone.
enum WatchSessionLog {
    struct Entry: Codable, Identifiable {
        var id: Date { start }
        let kind: String
        let start: Date
        let end: Date
        let reason: String
        let epochs: Int
        let peakActivity: Double
    }

    private static let key = "watchSessionLog"

    static func load() -> [Entry] {
        let raw = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        return raw.compactMap { try? JSONDecoder().decode(Entry.self, from: $0) }.sorted { $0.start > $1.start }
    }

    static func append(_ data: Data) {
        let raw = (UserDefaults.standard.array(forKey: key) as? [Data] ?? []) + [data]
        UserDefaults.standard.set(Array(raw.suffix(100)), forKey: key)
    }
}
