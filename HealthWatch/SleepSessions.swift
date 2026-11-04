import Foundation
import Observation
import WatchKit
import CoreMotion
import HealthKit
import WatchConnectivity
import HealthCore

/// Turns the accelerometer into 30-second epochs: the mean absolute deviation of the acceleration magnitude from
/// its own mean (see `MotionEpoch`). Sampled at 10 Hz, enough to see a turn in bed while sparing the battery.
@MainActor
final class MotionSampler {
    private let motion = CMMotionManager()
    private var buffer: [Double] = []
    private var epochStart = Date()
    var latestHeartRate: Double?
    var onEpoch: ((MotionEpoch) -> Void)?

    func start() {
        guard motion.isAccelerometerAvailable else { return }
        buffer = []
        epochStart = .now
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let a = data?.acceleration else { return }
            MainActor.assumeIsolated { self?.add((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()) }
        }
    }

    func stop() { motion.stopAccelerometerUpdates() }

    private func add(_ magnitude: Double) {
        buffer.append(magnitude)
        guard Date.now.timeIntervalSince(epochStart) >= 30, let mean = Stats.mean(buffer) else { return }
        let mad = buffer.reduce(0) { $0 + abs($1 - mean) } / Double(buffer.count)
        onEpoch?(MotionEpoch(time: epochStart, activity: mad, heartRate: latestHeartRate))
        buffer = []
        epochStart = .now
    }
}

/// What happened in a session, kept for tuning the thresholds and sent to the phone.
struct SessionLogEntry: Codable, Identifiable {
    var id: Date { start }
    let kind: String              // "alarm", "nap", "desk"
    let start: Date
    let end: Date
    let reason: String            // wake reason, or "2 nudges" for desk mode
    let epochs: Int
    let peakActivity: Double
}

enum SessionLog {
    static let key = "sessionLog"

    static func load() -> [SessionLogEntry] {
        guard let data = UserDefaults(suiteName: SharedKeys.group)?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SessionLogEntry].self, from: data)) ?? []
    }

    static func append(_ e: SessionLogEntry) {
        let all = Array((load() + [e]).suffix(60))
        UserDefaults(suiteName: SharedKeys.group)?.set(try? JSONEncoder().encode(all), forKey: key)
        if WCSession.default.activationState == .activated, let data = try? JSONEncoder().encode(e) {
            WCSession.default.transferUserInfo([key: data])
        }
    }
}

/// Smart alarm and smart nap, both on Apple's smart-alarm extended runtime session: up to 30 minutes in the
/// background with motion, ending in a repeating haptic until you stop it. Apple allows one scheduled session at
/// a time and only from the foreground, so the next morning's alarm is scheduled whenever the app is open: after
/// you stop an alarm or a nap, or when you open the app.
@MainActor
@Observable
final class SleepSessions: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = SleepSessions()

    enum Mode: Equatable { case idle, alarmScheduled(Date), watching, napping(asleepSince: Date?), ringing(String) }

    var mode: Mode = .idle
    var alarmEnabled: Bool = UserDefaults.standard.bool(forKey: "smartAlarmOn") {
        didSet {
            UserDefaults.standard.set(alarmEnabled, forKey: "smartAlarmOn")
            if alarmEnabled { scheduleMorning() } else { cancel() }
        }
    }
    var windowMinutes: Double = UserDefaults.standard.object(forKey: "smartAlarmWindow") as? Double ?? 30 {
        didSet {
            UserDefaults.standard.set(windowMinutes, forKey: "smartAlarmWindow")
            if alarmEnabled { cancel(); scheduleMorning() }
        }
    }
    var napMinutes: Double = 15

    private var session: WKExtendedRuntimeSession?
    private var kind = "alarm"
    private var wakeBy = Date()
    private var started = Date()
    private var epochs: [MotionEpoch] = []
    private let sampler = MotionSampler()

    /// Wake goal from the phone (minutes after midnight), 07:40 until the phone has sent one.
    var wakeGoal: Double = UserDefaults(suiteName: SharedKeys.group)?.object(forKey: SharedKeys.wakeGoal) as? Double ?? 460

    /// Set the wake time on the watch: kept here, sent to the phone so its setting follows, and the alarm moved.
    func setWakeGoal(_ minutes: Double) {
        wakeGoal = SleepPlan.wrap(minutes)
        let d = UserDefaults(suiteName: SharedKeys.group)
        d?.set(wakeGoal, forKey: SharedKeys.wakeGoal)
        d?.set(Date.now, forKey: SharedKeys.wakeGoalSetAt)
        if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo([SharedKeys.wakeGoal: wakeGoal])
        }
        if alarmEnabled, session == nil || isScheduledOnly { cancel(); scheduleMorning() }
    }

    /// Picks up a wake goal the phone sent.
    func reloadWakeGoal() {
        wakeGoal = UserDefaults(suiteName: SharedKeys.group)?.object(forKey: SharedKeys.wakeGoal) as? Double ?? 460
        if alarmEnabled, isScheduledOnly, case .alarmScheduled(let d) = mode, d != nextWake() { cancel(); scheduleMorning() }
    }

    private var isScheduledOnly: Bool { if case .alarmScheduled = mode { true } else { mode == .idle } }

    /// The next wake time: today if it hasn't passed yet (with time to start the window), else tomorrow.
    func nextWake(after now: Date = .now) -> Date {
        let today = Calendar.current.startOfDay(for: now).addingTimeInterval(wakeGoal * 60)
        return today.addingTimeInterval(-windowMinutes * 60) > now ? today : today.addingTimeInterval(86400)
    }

    func scheduleMorning() {
        guard alarmEnabled, session == nil || mode == .idle else { return }
        cancel()
        kind = "alarm"
        wakeBy = nextWake()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: wakeBy.addingTimeInterval(-windowMinutes * 60))
        session = s
        mode = .alarmScheduled(wakeBy)
    }

    func startNap() {
        cancel()
        kind = "nap"
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
        mode = .napping(asleepSince: nil)
    }

    func cancel() {
        session?.invalidate()
        session = nil
        sampler.stop()
        mode = .idle
    }

    /// Stop ringing, log what happened, and line up tomorrow's alarm while the app is in front.
    func stop() {
        let reason: String = if case .ringing(let r) = mode { r } else { "stopped" }
        SessionLog.append(SessionLogEntry(kind: kind, start: started, end: .now, reason: reason, epochs: epochs.count,
                                          peakActivity: epochs.map(\.activity).max() ?? 0))
        session?.invalidate()
        session = nil
        sampler.stop()
        mode = .idle
        scheduleMorning()
    }

    private func onEpoch(_ e: MotionEpoch) {
        epochs.append(e)
        switch kind {
        case "nap":
            switch NapPlan.decide(epochs, start: started, napMinutes: napMinutes, now: .now) {
            case .fallingAsleep: mode = .napping(asleepSince: nil)
            case .asleep(let since): mode = .napping(asleepSince: since)
            case .wake(let r): ring(r == .deadline ? "nap over" : r.rawValue)
            }
        default:
            if let r = SmartWake.decide(epochs, windowStart: started, wakeBy: wakeBy, now: .now) {
                ring(r == .deadline ? "wake time" : "light sleep: \(r.rawValue)")
            }
        }
    }

    private func ring(_ reason: String) {
        guard case .ringing = mode else {
            mode = .ringing(reason)
            sampler.stop()
            session?.notifyUser(hapticType: .notification) { _ in 4 }   // repeats every 4 s until stopped
            return
        }
    }

    // MARK: WKExtendedRuntimeSessionDelegate

    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in
            started = .now
            epochs = []
            if kind == "alarm" { mode = .watching }
            sampler.onEpoch = { [weak self] e in self?.onEpoch(e) }
            sampler.start()
        }
    }

    /// The session's 30 minutes are almost up: wake now rather than not at all.
    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in ring(kind == "nap" ? "nap over" : "wake time") }
    }

    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        let id = ObjectIdentifier(s)
        Task { @MainActor in
            guard let current = session, ObjectIdentifier(current) == id else { return }
            if case .ringing = mode { return }      // keep the ringing screen until you stop it
            session = nil
            mode = .idle
        }
    }
}

/// Desk mode: a workout session (so heart rate keeps flowing in the background) that watches for a still wrist and
/// a falling heart rate, and taps you to stand up. Nothing is saved to Health: the workout is discarded at the end.
/// Runs for at most two hours; it costs battery like a workout while on.
@MainActor
@Observable
final class DeskMode: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = DeskMode()

    var isOn = false
    var nudges = 0
    var lastNudge: Date?
    var heartRate: Double?
    var endsAt: Date?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var epochs: [MotionEpoch] = []
    private var started = Date()
    private let sampler = MotionSampler()
    static let maxDuration: TimeInterval = 2 * 3600
    static let cooldown: TimeInterval = 10 * 60

    func start() async {
        guard !isOn else { return }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [HKQuantityType(.heartRate)])
            let config = HKWorkoutConfiguration()
            config.activityType = .mindAndBody
            config.locationType = .indoor
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            started = .now
            endsAt = started.addingTimeInterval(Self.maxDuration)
            epochs = []
            nudges = 0
            s.startActivity(with: started)
            try await b.beginCollection(at: started)
            sampler.onEpoch = { [weak self] e in self?.onEpoch(e) }
            sampler.start()
            isOn = true
        } catch {
            isOn = false
        }
    }

    func stop() {
        sampler.stop()
        session?.end()
        let b = builder
        Task { try? await b?.endCollection(at: .now); b?.discardWorkout() }
        if isOn {
            SessionLog.append(SessionLogEntry(kind: "desk", start: started, end: .now, reason: "\(nudges) nudges",
                                              epochs: epochs.count, peakActivity: epochs.map(\.activity).max() ?? 0))
        }
        session = nil
        builder = nil
        isOn = false
        endsAt = nil
    }

    private func onEpoch(_ e: MotionEpoch) {
        epochs.append(e)
        if let end = endsAt, Date.now >= end { stop(); return }
        let cooled = lastNudge.map { Date.now.timeIntervalSince($0) >= Self.cooldown } ?? true
        if cooled, DozeDetector.isDozing(epochs, baselineHR: DozeDetector.baseline(epochs)) {
            WKInterfaceDevice.current().play(.notification)
            nudges += 1
            lastNudge = .now
        }
    }

    // MARK: Delegates

    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in stop() }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = b.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        Task { @MainActor in
            heartRate = hr
            sampler.latestHeartRate = hr
        }
    }
}
