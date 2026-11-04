import SwiftUI
import WatchConnectivity
import WidgetKit
import HealthKit
import HealthCore

/// The watch app: receives the day's numbers from the iPhone, keeps them for the complications, and shows them.
/// The watch never reads Apple Health itself; everything is computed on the phone.
@main
struct HealthWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchDelegate

    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .onChange(of: phase) { _, p in
                    // Apple only lets the app schedule a session while it is in front
                    if p == .active { SleepSessions.shared.scheduleMorning() }
                }
        }
    }
}

final class WatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() { PhoneLink.shared.activate() }

    /// The phone's "Start desk mode" shortcut launches the watch app with a workout configuration.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await DeskMode.shared.start() }
    }
}

/// The watch side of WatchConnectivity: stores what the phone sends in the App Group and reloads complications.
final class PhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneLink()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func store(_ payload: [String: Any]) {
        guard let d = UserDefaults(suiteName: SharedKeys.group) else { return }
        let sent = (payload[SharedKeys.date] as? Double).map { Date(timeIntervalSince1970: $0) }
        // A wake time set on the watch wins over anything the phone sent before it heard about it
        let keepWatchWake = (d.object(forKey: SharedKeys.wakeGoalSetAt) as? Date).map { set in sent.map { $0 < set } ?? true } ?? false
        for k in SharedKeys.all where k != SharedKeys.date && !(k == SharedKeys.wakeGoal && keepWatchWake) {
            d.set(payload[k], forKey: k)
        }
        if let sent { d.set(sent, forKey: SharedKeys.date) }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: .dayUpdated, object: nil)
        Task { @MainActor in SleepSessions.shared.reloadWakeGoal() }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty { store(session.receivedApplicationContext) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { store(applicationContext) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { store(userInfo) }
}

extension Notification.Name {
    static let dayUpdated = Notification.Name("dayUpdated")
}

struct WatchDayView: View {
    @State private var day = WatchDay.load()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [day.statusColor.opacity(0.55), day.statusColor],
                                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 70))
                    VStack(spacing: 0) {
                        Text(day.statusWord).font(.system(.title3, design: .rounded).weight(.bold))
                        Text(day.isToday ? "recovery \(day.text(day.score, 0))" : "open the iPhone app").font(.caption2)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 110, height: 110)
                HStack {
                    tile("sleep", day.text(day.sleep, 0), WatchDay.sleepColor)
                    tile("strain", day.text(day.strain, 1), WatchDay.strainColor)
                }
                if let lo = day.strainLow, let hi = day.strainHigh, day.isToday {
                    Text("Strain target \(Int(lo.rounded()))-\(Int(hi.rounded()))").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayUpdated)) { _ in day = WatchDay.load() }
        .onAppear { day = WatchDay.load() }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WatchRoot: View {
    @State private var sessions = SleepSessions.shared

    var body: some View {
        if case .ringing(let reason) = sessions.mode {
            RingingView(reason: reason) { sessions.stop() }
        } else {
            TabView {
                WatchDayView()
                AlarmView()
                NapView()
                DeskView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

struct RingingView: View {
    let reason: String
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.orange)
            Text("Time to get up").font(.headline)
            Text(reason).font(.caption2).foregroundStyle(.secondary)
            Button("Stop", action: stop).buttonStyle(.borderedProminent).tint(.orange)
        }
    }
}

/// Smart alarm: wakes you in the window before your wake goal at the first sign of light sleep (`SmartWake`).
struct AlarmView: View {
    @State private var s = SleepSessions.shared
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Toggle("Smart alarm", isOn: Binding(get: { s.alarmEnabled }, set: { s.alarmEnabled = $0 }))
                Button { editing = true } label: {
                    VStack(spacing: 0) {
                        Text("Wake by").font(.caption2).foregroundStyle(.secondary)
                        Text(WakeTimeEditor.clock(s.wakeGoal)).font(.system(.title2, design: .rounded).weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Window, minutes").font(.caption2).foregroundStyle(.secondary)
                ChoiceRow(options: [10, 20, 30], value: Binding(get: { s.windowMinutes }, set: { s.windowMinutes = $0 }), tint: .orange)
                Text(status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .sheet(isPresented: $editing) { WakeTimeEditor() }
    }

    private var status: String {
        switch s.mode {
        case .alarmScheduled(let d): "Set. Wakes you between \(d.addingTimeInterval(-s.windowMinutes * 60).formatted(date: .omitted, time: .shortened)) and \(d.formatted(date: .omitted, time: .shortened)) when you stir."
        case .watching: "Watching for light sleep."
        case .napping: "A nap is running; the alarm is set again after it."
        default: s.alarmEnabled ? "Open the app once in the evening so it can set tomorrow's alarm." : "Off. Keep a normal alarm as backup the first nights."
        }
    }
}

/// Smart nap: counts the nap from when you fall asleep, capped at 30 minutes (`NapPlan`).
struct NapView: View {
    @State private var s = SleepSessions.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Smart nap").font(.headline)
                if case .napping(let since) = s.mode {
                    Text(since.map { "Asleep since " + $0.formatted(date: .omitted, time: .shortened) } ?? "Waiting for you to fall asleep")
                        .font(.footnote).multilineTextAlignment(.center)
                    Button("Cancel", role: .destructive) { s.cancel() }
                } else {
                    Text("Sleep for, minutes").font(.caption2).foregroundStyle(.secondary)
                    ChoiceRow(options: [10, 15, 20], value: $s.napMinutes, tint: .purple)
                    Button("Start nap") { s.startNap() }.buttonStyle(.borderedProminent).tint(.purple)
                    Text("Counts from when you fall asleep, and wakes you by 30 minutes at the latest so you don't drift into deep sleep.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
    }
}

/// Desk mode: taps you to stand up when your wrist goes still and your heart rate drops (`DozeDetector`).
struct DeskView: View {
    @State private var d = DeskMode.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Desk mode").font(.headline)
                if d.isOn {
                    Text(d.heartRate.map { "\(Int($0)) bpm" } ?? "Reading heart rate…").font(.title3)
                    Text("\(d.nudges) nudge\(d.nudges == 1 ? "" : "s")" + (d.endsAt.map { ", ends " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                        .font(.footnote)
                    Button("Stop", role: .destructive) { d.stop() }
                } else {
                    Button("Start") { Task { await d.start() } }.buttonStyle(.borderedProminent).tint(.blue)
                    Text("Taps you to stand up if you start nodding off. Runs up to 2 hours, uses battery like a workout, and saves nothing to Health.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
    }
}

/// Three big buttons instead of a wheel, which is fiddly to land on the small screen.
struct ChoiceRow: View {
    let options: [Double]
    @Binding var value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { o in
                Button { value = o } label: {
                    Text("\(Int(o))").font(.headline).frame(maxWidth: .infinity, minHeight: 38)
                        .background(Capsule().fill(value == o ? tint : Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Wake time on the watch, set like the Alarm app: an hour wheel and a minute wheel, each turned with the
/// Digital Crown after tapping it.
struct WakeTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hour = Int(SleepSessions.shared.wakeGoal) / 60
    @State private var minute = Int(SleepSessions.shared.wakeGoal) % 60

    static func clock(_ m: Double) -> String {
        let r = Int(SleepPlan.wrap(m).rounded()) % 1440
        return String(format: "%02d:%02d", r / 60, r % 60)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Picker("Hour", selection: $hour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                Text(":").font(.title2.weight(.semibold))
                Picker("Minute", selection: $minute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .frame(height: 90)
            Button("Set") {
                SleepSessions.shared.setWakeGoal(Double(hour * 60 + minute))
                dismiss()
            }
            .buttonStyle(.borderedProminent).tint(.orange)
        }
        .navigationTitle("Wake by")
    }
}
