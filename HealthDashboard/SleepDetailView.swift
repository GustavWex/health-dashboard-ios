import SwiftUI
import Charts
import HealthCore

extension ScoreStatus {
    var color: Color {
        switch self {
        case .good: Zone.push.color
        case .fair: Zone.moderate.color
        case .poor: Zone.recover.color
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .fair: "exclamationmark.triangle.fill"
        case .poor: "exclamationmark.octagon.fill"
        }
    }
}

extension SleepComponentKind {
    var title: String {
        switch self {
        case .duration: "Duration"
        case .interruptions: "Interruptions"
        case .regularity: "Regularity"
        case .hrv: "HRV"
        case .heartRate: "Heart rate"
        case .depth: "Depth"
        }
    }

    func valueText(_ c: SleepComponent, night: SleepNight) -> String {
        switch self {
        case .duration: fmt(c.value, 1, " h")
        case .interruptions: night.awakenings == 1 ? "1 time" : "\(night.awakenings) times"
        case .regularity: fmt(c.value, 0)
        case .hrv: fmt(c.value, 0, " ms")
        case .heartRate: fmt(c.value, 0, " bpm")
        case .depth: fmt(c.value, 0, "%")
        }
    }

    var explanation: String {
        switch self {
        case .duration:
            "Time asleep against your sleep need from Settings. Half your need scores 0 and your full need scores 100."
        case .interruptions:
            "Time awake between falling asleep and your final wake-up. Up to 30 minutes is common and scores full marks, falling to 0 at 2 hours. Awakenings count wake bouts of \(Int(SleepGrouping.minAwakening / 60)) minutes or more; shorter stirs are drawn faded in the chart."
        case .regularity:
            "Sleep Regularity Index over the last 7 days: how likely you are to be in the same state, asleep or awake, at the same clock time on consecutive days. 100 is perfectly regular. From Phillips et al. 2017."
        case .hrv:
            "Average HRV while asleep, compared with your last 60 nights. At or above your usual level scores 100, 3 SD below scores 0."
        case .heartRate:
            "Average heart rate while asleep, compared with your last 60 nights. At or below your usual level scores 100, 3 SD above scores 0."
        case .depth:
            "Share of sleep in the deep and REM stages, compared with your own usual share. Watch stage estimates are rough, so this marker has the smallest weight."
        }
    }
}

extension SleepStage {
    var label: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .unspecified: "Asleep"
        case .inBed: "In bed"
        }
    }

    var color: Color {
        switch self {
        case .awake: .orange
        case .rem: .cyan
        case .core: .blue
        case .deep: .indigo
        case .unspecified: .teal
        case .inBed: .gray
        }
    }
}

struct SleepDetailView: View {
    let model: DashboardModel
    @State private var range = Range.day
    @State private var index: Int?

    enum Range: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

    private var nights: [SleepNight] { model.snapshot.sleep }
    private var selected: Int { min(index ?? nights.count - 1, nights.count - 1) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                if nights.isEmpty {
                    Text("No sleep found in Apple Health.").foregroundStyle(.secondary)
                } else if range == .day {
                    pager
                    NightView(model: model, night: nights[selected])
                } else {
                    PeriodView(model: model, nights: Array(nights.suffix(range == .week ? 7 : 30)))
                }
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pager: some View {
        HStack {
            Button { index = max(0, selected - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(selected == 0)
                .accessibilityLabel("Previous night")
            Spacer()
            Text("Night to " + nights[selected].date.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.headline)
            Spacer()
            Button { index = min(nights.count - 1, selected + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(selected == nights.count - 1)
                .accessibilityLabel("Next night")
        }
        .buttonStyle(.bordered)
    }
}

/// One night: score, the six parts, hypnogram and the night's readings.
struct NightView: View {
    let model: DashboardModel
    let night: SleepNight

    private var score: SleepScore { model.sleepScore(for: night) }
    private var window: ClosedRange<Date> {
        night.start.addingTimeInterval(-Overnight.margin)...night.end.addingTimeInterval(Overnight.margin)
    }

    var body: some View {
        Card(title: "Sleep score", systemImage: "moon.zzz") {
            HStack(spacing: 20) {
                RecoveryRing(score: score.score, color: Palette.sleep, caption: "sleep")
                VStack(alignment: .leading, spacing: 4) {
                    Text(fmt(night.asleep / 3600, 1, " h asleep")).font(.headline)
                    Text(SleepPlanText.clock(SleepPlan.clock(night.start)) + " to "
                         + SleepPlanText.clock(SleepPlan.clock(night.end)))
                        .foregroundStyle(.secondary)
                    Text("Our own score, built from the same markers as the Withings one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(score.components) { c in
                    NavigationLink {
                        ComponentDetailView(model: model, kind: c.kind, night: night)
                    } label: {
                        ComponentTile(component: c, night: night)
                    }
                    .buttonStyle(.plain)
                }
            }
            let lost = score.pointsLost.filter { $0.points >= 1 }.prefix(3)
            if !lost.isEmpty {
                Divider()
                Text("Where the points went").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(lost), id: \.kind) { l in
                    if let c = score.component(l.kind) {
                        HStack {
                            Text(l.kind.title)
                            Text(l.kind.valueText(c, night: night)).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "−%.0f", l.points)).monospacedDigit().foregroundStyle(Zone.recover.color)
                        }
                        .font(.subheadline)
                    }
                }
                Text("Each marker's cost against a perfect 100. They add up to the gap, because the score is a weighted average.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        if let room = RoomEngine.nights(model.snapshot.room, sleep: [night]).first, room.co2Mean != nil {
            Card(title: "Bedroom air", systemImage: "wind") {
                RoomNightChart(night: room)
                Text("CO2 in the room through the night. Dashed amber is 2,000 ppm.").font(.caption2).foregroundStyle(.secondary)
            }
        }

        Card(title: "Stages", systemImage: "chart.bar.xaxis") {
            Hypnogram(night: night)
            Text("Faded orange marks brief stirs under \(Int(SleepGrouping.minAwakening / 60)) minutes. They don't count as awakenings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        let hr = model.snapshot.nightHeartRate.filter { window.contains($0.date) }
        if !hr.isEmpty {
            Card(title: "Heart rate", systemImage: "heart") {
                ReadingChart(readings: hr, unit: "bpm", color: Palette.heart)
                stats(hr, unit: "bpm", digits: 0)
            }
        }

        let hrv = model.snapshot.nightHRV.filter { window.contains($0.date) }
        if !hrv.isEmpty {
            Card(title: "HRV", systemImage: "waveform.path.ecg") {
                ReadingChart(readings: hrv, unit: "ms", color: Palette.heart, points: true)
                stats(hrv, unit: "ms", digits: 0)
                Text("The watch takes only a few HRV readings per night, so read the trend over nights, not one reading.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        let resp = model.snapshot.nightRespiratory.filter { window.contains($0.date) }
        if !resp.isEmpty || model.snapshot.breathingDisturbances.value(on: night.date) != nil {
            Card(title: "Breathing", systemImage: "lungs") {
                if !resp.isEmpty {
                    ReadingChart(readings: resp, unit: "/min", color: Palette.heart)
                    stats(resp, unit: "/min", digits: 1)
                }
                if let d = model.snapshot.breathingDisturbances.value(on: night.date) {
                    LabeledContent("Breathing disturbances", value: fmt(d, 1, " per hour"))
                        .font(.subheadline)
                } else {
                    Text("Breathing disturbances need a newer Apple Watch, so this shows breathing rate only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stats(_ r: [Reading], unit: String, digits: Int) -> some View {
        let v = r.map(\.value)
        return HStack {
            MetricTile(label: "Average", value: fmt(Stats.mean(v), digits, " " + unit))
            MetricTile(label: "Range", value: fmt(v.min(), digits) + " to " + fmt(v.max(), digits, " " + unit))
        }
    }
}

struct ComponentTile: View {
    let component: SleepComponent
    let night: SleepNight

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.kind.title).font(.caption).foregroundStyle(.secondary)
                Text(component.kind.valueText(component, night: night))
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: component.status.symbol).foregroundStyle(component.status.color)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Stage timeline like Apple Health's, with short wake stirs faded so the night doesn't look twitchy.
struct Hypnogram: View {
    let night: SleepNight

    private var rows: [String] {
        let present = Set(night.stages.map(\.stage))
        return [SleepStage.awake, .rem, .core, .deep, .unspecified].filter { present.contains($0) }.map(\.label)
    }

    private var countedBouts: [DateInterval] {
        SleepGrouping.wakeBouts(of: night).filter { $0.duration >= SleepGrouping.minAwakening }
    }

    private func isBrief(_ s: StageInterval) -> Bool {
        s.stage == .awake && !countedBouts.contains { $0.intersects(DateInterval(start: s.start, end: s.end)) }
    }

    var body: some View {
        if night.stages.isEmpty {
            Text("No stage data for this night.").foregroundStyle(.secondary).frame(height: 160)
        } else {
            Chart(Array(night.stages.enumerated()), id: \.offset) { _, s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end), y: .value("Stage", s.stage.label))
                    .foregroundStyle(s.stage.color.opacity(isBrief(s) ? 0.3 : 1))
            }
            .chartYScale(domain: rows)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                }
            }
            .frame(height: 180)
        }
    }
}

struct ReadingChart: View {
    let readings: [Reading]
    let unit: String
    let color: Color
    var points = false

    var body: some View {
        Chart(Array(readings.enumerated()), id: \.offset) { _, r in
            if points {
                PointMark(x: .value("Time", r.date), y: .value(unit, r.value))
                    .foregroundStyle(color)
            } else {
                LineMark(x: .value("Time", r.date), y: .value(unit, r.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
            }
        }
        .frame(height: 140)
    }
}

/// Week or month: stages per night and the average score.
struct PeriodView: View {
    let model: DashboardModel
    let nights: [SleepNight]

    private struct Bar: Identifiable {
        let date: Date
        let stage: String
        let hours: Double
        let color: Color
        var id: String { "\(date.timeIntervalSince1970)\(stage)" }
    }

    private var bars: [Bar] {
        nights.flatMap { n -> [Bar] in
            let other = max(0, n.asleep - n.deep - n.rem - n.core)
            return [
                Bar(date: n.date, stage: "Deep", hours: n.deep / 3600, color: SleepStage.deep.color),
                Bar(date: n.date, stage: "Core", hours: n.core / 3600, color: SleepStage.core.color),
                Bar(date: n.date, stage: "REM", hours: n.rem / 3600, color: SleepStage.rem.color),
                Bar(date: n.date, stage: "Asleep", hours: other / 3600, color: SleepStage.unspecified.color),
            ].filter { $0.hours > 0 }
        }
    }

    var body: some View {
        let scores = nights.map { model.sleepScore(for: $0).score }
        Card(title: "Averages", systemImage: "sum") {
            HStack {
                MetricTile(label: "Sleep score", value: fmt(Stats.mean(scores), 0))
                MetricTile(label: "Asleep", value: fmt(Stats.mean(nights.map { $0.asleep / 3600 }), 1, " h"))
                MetricTile(label: "Awakenings", value: fmt(Stats.mean(nights.map { Double($0.awakenings) }), 1))
            }
        }
        Card(title: "Stages per night", systemImage: "chart.bar") {
            Chart(bars) { b in
                BarMark(x: .value("Night", b.date, unit: .day), y: .value("Hours", b.hours))
                    .foregroundStyle(by: .value("Stage", b.stage))
            }
            .chartForegroundStyleScale(["Deep": SleepStage.deep.color, "Core": SleepStage.core.color,
                                        "REM": SleepStage.rem.color, "Asleep": SleepStage.unspecified.color])
            .frame(height: 200)
        }
        Card(title: "Sleep score per night", systemImage: "moon.zzz") {
            Chart(Array(zip(nights, scores)), id: \.0.date) { n, s in
                BarMark(x: .value("Night", n.date, unit: .day), y: .value("Score", s))
                    .foregroundStyle(ScoreStatus(s).color)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 160)
        }
    }
}

/// One score part over the last 30 nights, with how it is calculated.
struct ComponentDetailView: View {
    let model: DashboardModel
    let kind: SleepComponentKind
    let night: SleepNight

    var body: some View {
        let recent = Array(model.snapshot.sleep.filter { $0.date <= night.date }.suffix(30))
        let points = recent.compactMap { n in model.sleepScore(for: n).component(kind).map { (n.date, $0.score) } }
        ScrollView {
            VStack(spacing: 14) {
                if let c = model.sleepScore(for: night).component(kind) {
                    Card(title: kind.title, systemImage: c.status.symbol) {
                        Text(kind.valueText(c, night: night))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        Text("Scores \(Int(c.score.rounded())) of 100").foregroundStyle(c.status.color)
                    }
                }
                Card(title: "Last 30 nights", systemImage: "chart.bar") {
                    Chart(points, id: \.0) { date, score in
                        BarMark(x: .value("Night", date, unit: .day), y: .value("Score", score))
                            .foregroundStyle(ScoreStatus(score).color)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 160)
                }
                Card(title: "How it works", systemImage: "info.circle") {
                    Text(kind.explanation).font(.subheadline)
                }
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
/// Raw wake bouts per night, to calibrate `SleepGrouping.minAwakening` against the Withings count.
struct AwakeningCalibrationView: View {
    let model: DashboardModel
    private let thresholds: [Double] = [1, 2, 3, 5]

    var body: some View {
        List {
            Section {
                Text("Compare a night here with the Withings interruptions count, and use the column that matches. Merged means wake bouts under \(Int(SleepGrouping.awakeningMergeGap / 60)) min apart count once.")
                    .font(.footnote)
            }
            ForEach(model.snapshot.sleep.suffix(10).reversed()) { n in
                let raw = SleepGrouping.wakeBouts(of: n, mergeGap: 0)
                let merged = SleepGrouping.wakeBouts(of: n)
                Section(n.date.formatted(.dateTime.weekday(.abbreviated).day().month())) {
                    LabeledContent("Raw wake samples", value: "\(raw.count)")
                    ForEach(thresholds, id: \.self) { t in
                        LabeledContent("Merged, \(Int(t)) min or more", value: "\(merged.filter { $0.duration >= t * 60 }.count)")
                    }
                    LabeledContent("Wake after sleep onset", value: "\(Int(n.waso / 60)) min")
                    Text(merged.map { "\(Int(($0.duration / 60).rounded()))" }.joined(separator: ", ") + " min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Awakening calibration")
    }
}
#endif
