import SwiftUI
import Charts
import HealthCore

extension Zone {
    var title: String {
        switch self {
        case .recover: "Recover"
        case .moderate: "Moderate"
        case .push: "Push"
        }
    }

    var color: Color {
        switch self {
        case .recover: Color(red: 0.86, green: 0.27, blue: 0.30)
        case .moderate: Color(red: 0.93, green: 0.67, blue: 0.18)
        case .push: Color(red: 0.20, green: 0.70, blue: 0.47)
        }
    }
}

/// One colour per area, used for its dials, chart lines and icons everywhere. Green, yellow and red are kept
/// for meaning (good, caution, bad: recovery zones and status) and never identify an area.
enum Palette {
    static let sleep = Color(red: 0.58, green: 0.44, blue: 0.95)      // purple
    static let strain = Color(red: 0.16, green: 0.47, blue: 0.95)     // blue: training and activity, like WHOOP's strain
    static let heart = Color(red: 0.13, green: 0.66, blue: 0.74)      // teal: HRV, resting HR, breathing
    static let body = Color(red: 0.95, green: 0.58, blue: 0.20)       // amber: weight and composition
    static let nutrition = Color(red: 0.89, green: 0.35, blue: 0.56)  // pink: food
    static let air = Color(red: 0.42, green: 0.74, blue: 0.86)        // sky: bedroom air and light
    static var good: Color { Zone.push.color }
    static var caution: Color { Zone.moderate.color }
    static var bad: Color { Zone.recover.color }
}

extension Color {
    /// Mixed towards white by `amount` (0 to 1), for the light centre of a gradient blob.
    func lighter(_ amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let t = CGFloat(amount)
        return Color(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, opacity: a)
    }
}

/// Warm light theme taken from the app icon: a soft red, coral and amber glow on warm white.
enum Theme {
    static let paper = Color(red: 0.976, green: 0.965, blue: 0.929)    // the icon's background, #F9F6ED
    static let ink = Color(red: 0.17, green: 0.12, blue: 0.10)         // warm near-black for text
    static let accent = Color(red: 0.91, green: 0.33, blue: 0.24)      // coral, between the icon's red and orange
    static let glow = [Color(red: 0.88, green: 0.18, blue: 0.24), Color(red: 0.97, green: 0.50, blue: 0.20),
                       Color(red: 0.99, green: 0.76, blue: 0.33)]
}

/// The page background: warm paper with three large, very soft colour glows from the icon, so the frosted
/// cards above it pick up a little warmth. Static, so it costs nothing while scrolling.
struct AmbientBackground: View {
    /// When set (Today), the glows take this colour, the merged blob's green, yellow or red.
    var tint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let colors = tint.map { [$0, $0.lighter(0.25), $0.lighter(0.5)] } ?? Theme.glow
            ZStack {
                Theme.paper
                glow(colors[0], 0.16, size: w * 1.1).position(x: w * 0.05, y: h * 0.08)
                glow(colors[1], 0.14, size: w * 1.2).position(x: w * 0.98, y: h * 0.42)
                glow(colors[2], 0.18, size: w * 1.2).position(x: w * 0.2, y: h * 0.95)
            }
            .animation(.easeInOut(duration: 0.8), value: tint)
        }
        .ignoresSafeArea()
    }

    private func glow(_ c: Color, _ opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(opacity), c.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

extension View {
    /// Frosted glass card for content (glassmorphism): a light material over the warm background, a hairline
    /// white edge and a soft shadow. Apple reserves Liquid Glass (`glassEffect`) for the controls layer that
    /// floats above content, so content cards use a material instead and stay easy to read.
    func glassCard(_ radius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .background(Color.white.opacity(0.38), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 0.75))
            .shadow(color: Theme.ink.opacity(0.06), radius: 14, y: 6)
    }

    /// Lists and forms on the warm background instead of system grey, with frosted rows.
    func ambientList() -> some View {
        self.scrollContentBackground(.hidden).background(AmbientBackground())
    }

    /// Liquid Glass buttons on iOS 26 and later (Apple's controls layer); bordered buttons before that.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

func fmt(_ v: Double?, _ digits: Int = 0, _ suffix: String = "") -> String {
    guard let v else { return "--" }
    return String(format: "%.\(digits)f", v) + suffix
}

func zText(_ z: Double?) -> String? {
    guard let z else { return nil }
    if abs(z) < 0.5 { return "at baseline" }
    return String(format: "%.1f SD %@", abs(z), z > 0 ? "above" : "below")
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one bold element on the Today screen.
/// A WHOOP-style dial: a ring filled to value / max with the number in the middle.
struct ScoreRing: View {
    let value: Double?
    var maxValue: Double = 100
    var text: String? = nil          // defaults to the rounded value
    let caption: String
    let color: Color
    var size: CGFloat = 136

    private var line: CGFloat { size * 0.11 }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, max(0, (value ?? 0) / maxValue)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: value)
            VStack(spacing: 0) {
                Text(text ?? value.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(line)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption.capitalized) \(text ?? value.map { "\(Int($0.rounded()))" } ?? "unknown")")
    }
}

struct RecoveryRing: View {
    let score: Double?
    let color: Color
    var caption = "recovery"

    var body: some View { ScoreRing(value: score, caption: caption, color: color) }
}

struct StagePart: Identifiable {
    let name: String
    let seconds: TimeInterval
    let color: Color
    var id: String { name }
}

struct StageBar: View {
    let night: SleepNight

    private var parts: [StagePart] {
        let staged = night.deep + night.core + night.rem
        var p = [
            StagePart(name: "Deep", seconds: night.deep, color: .indigo),
            StagePart(name: "Core", seconds: night.core, color: .blue),
            StagePart(name: "REM", seconds: night.rem, color: .cyan),
        ]
        if night.asleep - staged > 60 {
            p.append(StagePart(name: "Asleep", seconds: night.asleep - staged, color: .teal))
        }
        p.append(StagePart(name: "Awake", seconds: night.awake, color: .orange))
        return p.filter { $0.seconds > 0 }
    }

    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.seconds }, 1)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts) { p in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(p.color)
                            .frame(width: max(0, geo.size.width * p.seconds / total - 2))
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 10) {
                ForEach(parts) { p in
                    Text("\(p.name) \(Int(p.seconds / 60))m")
                        .font(.caption2)
                        .foregroundStyle(p.color)
                }
            }
        }
    }
}

/// Touch and drag on a chart to read the exact value of the nearest day.
enum ChartSelection {
    static func nearest(_ points: [DailyValue], to date: Date?) -> DailyValue? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    static func valueText(_ v: Double, unit: String) -> String {
        let digits = abs(v) >= 100 ? 0 : 1
        return v.formatted(.number.precision(.fractionLength(0...digits))) + (unit.isEmpty ? "" : " " + unit)
    }

    /// The callout shown above the selected point: value first, date under it.
    static func callout(_ p: DailyValue, unit: String) -> some View {
        VStack(spacing: 1) {
            Text(valueText(p.value, unit: unit)).font(.caption.weight(.bold)).monospacedDigit()
            Text(p.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.12), radius: 2)
    }
}

struct LineTrend: View {
    let points: [DailyValue]
    let unit: String
    var color: Color = .accentColor
    var baseline: Double? = nil
    @State private var selected: Date?

    var body: some View {
        if points.isEmpty {
            Text("No data yet").foregroundStyle(.secondary).frame(height: 160)
        } else {
            let pick = ChartSelection.nearest(points, to: selected)
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
                if let baseline {
                    RuleMark(y: .value("Baseline", baseline))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                if let pick {
                    RuleMark(x: .value("Selected", pick.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartSelection.callout(pick, unit: unit)
                        }
                    PointMark(x: .value("Day", pick.date, unit: .day), y: .value(unit, pick.value))
                        .foregroundStyle(color)
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 160)
            .padding(.top, 24)
        }
    }
}

struct BarTrend: View {
    let points: [DailyValue]
    let unit: String
    var color: Color = .accentColor
    var rule: Double? = nil
    @State private var selected: Date?

    var body: some View {
        if points.isEmpty {
            Text("No data yet").foregroundStyle(.secondary).frame(height: 160)
        } else {
            let pick = ChartSelection.nearest(points, to: selected)
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(pick == nil || pick?.date == p.date ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.35)))
                }
                if let rule {
                    RuleMark(y: .value("Target", rule))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                if let pick {
                    RuleMark(x: .value("Selected", pick.date, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartSelection.callout(pick, unit: unit)
                        }
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 160)
            .padding(.top, 24)
        }
    }
}

