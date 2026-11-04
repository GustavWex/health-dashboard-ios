import SwiftUI
import HealthCore

/// Overnight vitals in the style of Apple's Vitals app: one column per reading, your typical range as a shaded
/// band, last night as a dot and the six nights before as faint dots. Inside the band is normal for you.
struct OvernightVitals: View {
    let model: DashboardModel

    private var checks: [VitalCheck] { model.vitals?.checks ?? [] }
    private var unusual: [VitalCheck] { checks.filter { $0.status == .low || $0.status == .high } }

    var body: some View {
        NavigationLink {
            DetailPage(title: "Overnight vitals") { VitalsCard(model: model) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Overnight vitals").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(unusual.isEmpty ? Color.secondary : Palette.caution)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if checks.isEmpty {
                    Text("Wear your watch to bed to see your overnight readings.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(checks) { c in
                            VitalColumn(check: c).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding()
            .glassCard(16)
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        if checks.isEmpty { return "" }
        if unusual.isEmpty { return checks.contains { $0.status == .normal } ? "All in your typical range" : "Learning your range" }
        return "\(unusual.count) outside your typical range"
    }
}

struct VitalColumn: View {
    let check: VitalCheck
    private let height: CGFloat = 92

    private var outside: Bool { check.status == .low || check.status == .high }

    var body: some View {
        VStack(spacing: 6) {
            Text(valueText)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(outside ? Palette.caution : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .top) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(width: 6).frame(maxWidth: .infinity)
                    if let lo = check.low, let hi = check.high {
                        let (bandTop, bandBottom) = (y(hi), y(lo))
                        Capsule()
                            .fill(Palette.heart.opacity(0.25))
                            .frame(width: 18, height: max(8, bandBottom - bandTop))
                            .offset(y: bandTop)
                            .frame(maxWidth: .infinity)
                        ForEach(check.recent.dropLast()) { p in
                            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 5, height: 5)
                                .offset(y: y(p.value) - 2.5)
                                .frame(maxWidth: .infinity)
                        }
                        if let v = check.value {
                            Circle()
                                .fill(outside ? Palette.caution : Color.primary)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .offset(y: y(v) - 5.5)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(width: w, height: height)
            }
            .frame(height: height)
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(short).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(check.name) \(valueText), \(statusText)")
    }

    /// The band fills the middle half of the column; values beyond the axis are pinned to its ends.
    private func y(_ v: Double) -> CGFloat {
        guard let lo = check.low, let hi = check.high, hi > lo else { return height / 2 }
        let pad = (hi - lo) / 2
        let f = (v - (lo - pad)) / ((hi + pad) - (lo - pad))
        return height * (1 - CGFloat(min(1, max(0, f))))
    }

    private var valueText: String {
        guard let v = check.value else { return "--" }
        let digits = ["bpm", "ms", "%"].contains(check.unit) ? 0 : 1
        return fmt(v, digits)
    }

    private var statusText: String {
        switch check.status {
        case .normal: "in your typical range"
        case .low: "low for you"
        case .high: "high for you"
        case .learning: "learning your range"
        case .noReading: "no reading"
        }
    }

    private var short: String {
        switch check.name {
        case "Resting HR": "RHR"
        case "Breathing rate": "Breath"
        case "Wrist temperature": "Temp"
        case "Blood oxygen": "SpO₂"
        default: check.name
        }
    }

    private var icon: String {
        switch check.name {
        case "HRV": "waveform.path.ecg"
        case "Resting HR": "heart"
        case "Breathing rate": "lungs"
        case "Wrist temperature": "thermometer.medium"
        case "Blood oxygen": "drop"
        default: "bed.double"
        }
    }
}

/// The next mornings' recovery, inline on Today: one column per day, coloured by the zone it would land in.
struct NextDaysStrip: View {
    let model: DashboardModel

    var body: some View {
        NavigationLink {
            DetailPage(title: "Recovery forecast") {
                ForecastCard(model: model)
                ForecastExplanation(model: model)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recovery forecast").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("predicted morning recovery").font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if let days = model.readiness?.days, !days.isEmpty {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(days) { d in
                            VStack(spacing: 4) {
                                Text(fmt(d.planned, 0)).font(.caption.weight(.semibold)).monospacedDigit()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(zoneColor(d.planned).gradient)
                                    .frame(height: max(6, 56 * d.planned / 100))
                                Image(systemName: "dumbbell.fill").font(.caption2)
                                    .foregroundStyle(d.strengthPlanned ? Palette.strain : .clear)
                                Text(d.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 104, alignment: .bottom)
                    Text("Each bar is the recovery score expected on that morning if you keep your usual training rhythm. The dumbbell marks a planned strength session the day before.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
            .glassCard(16)
        }
        .buttonStyle(.plain)
    }

    private var message: String {
        if model.forecastPending { return "Fitting the model…" }
        if model.readiness == nil { return "A forecast needs about 75 mornings of recovery scores." }
        return "Hidden until the forecast beats \"tomorrow looks like today\"."
    }

    private func zoneColor(_ v: Double) -> Color {
        guard let r = model.recovery else { return Palette.heart }
        return v < r.low ? Zone.recover.color : (v >= r.high ? Zone.push.color : Zone.moderate.color)
    }
}
