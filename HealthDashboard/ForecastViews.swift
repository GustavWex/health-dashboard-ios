import SwiftUI
import Charts
import HealthCore

/// Today: recovery for the next mornings, shown only for horizons where the model beat "same as today".
struct ForecastCard: View {
    let model: DashboardModel

    var body: some View {
        Card(title: "Next days", systemImage: "chart.line.uptrend.xyaxis") {
            if model.forecastPending {
                ProgressView().frame(maxWidth: .infinity)
            } else if let f = model.readiness, !f.days.isEmpty {
                Chart {
                    ForEach(f.days) { d in
                        AreaMark(x: .value("Day", d.date, unit: .day),
                                 yStart: .value("Low", max(0, d.planned - d.band)),
                                 yEnd: .value("High", min(100, d.planned + d.band)))
                            .foregroundStyle(Palette.heart.opacity(0.12))
                        LineMark(x: .value("Day", d.date, unit: .day), y: .value("Recovery", d.planned))
                            .foregroundStyle(by: .value("Plan", "As usual"))
                            .symbol(.circle)
                        LineMark(x: .value("Day", d.date, unit: .day), y: .value("Recovery", d.rest))
                            .foregroundStyle(by: .value("Plan", "Rest"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                    }
                }
                .chartForegroundStyleScale(["As usual": Palette.heart, "Rest": Color.secondary])
                .chartYScale(domain: 0...100)
                .frame(height: 160)
                HStack {
                    ForEach(f.days) { d in
                        VStack(spacing: 2) {
                            Text(d.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                            Text(fmt(d.planned, 0)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Image(systemName: "dumbbell.fill").font(.caption2)
                                .foregroundStyle(d.strengthPlanned ? Palette.strain : .clear)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(caption(f))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let f = model.readiness {
                Text("The forecast doesn't beat \"tomorrow looks like today\" in your last \(f.skill.first?.n ?? 30) days yet, so it stays hidden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("A forecast needs about 75 mornings of recovery scores.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func caption(_ f: ReadinessForecast) -> String {
        let shown = f.skill.filter { $0.skill > 0 }
        let best = Int(((shown.map(\.skill).max() ?? 0) * 100).rounded())
        return "Dumbbell: a strength day from your rhythm the day before. Dashed: if you rest. The band is the typical miss over the last 30 days; the forecast is up to \(best)% closer than \"same as today\". Morning recovery wobbles a lot, so read it as a tendency."
    }
}

/// Insights: how a session shifts the next mornings, from the same model.
struct RecoveryCurveCard: View {
    let model: DashboardModel

    var body: some View {
        Card(title: "After a strength workout", systemImage: "waveform.path.ecg") {
            if let r = model.readiness {
                CurveChart(points: r.strengthCurve, unit: "points", color: Palette.heart)
                Text(summary(r.strengthCurve, unit: "recovery points"))
                    .font(.subheadline)
                if let h = model.hrvReadiness {
                    Text(summary(h.strengthCurve, unit: "% HRV"))
                        .font(.subheadline)
                }
                NavigationLink {
                    ModelDetailView(model: model)
                } label: {
                    HStack {
                        Text("How the model works")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            } else {
                Text(model.forecastPending ? "Fitting the model…" : "Needs about 45 mornings with recovery scores and some workouts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ c: [CurvePoint], unit: String) -> String {
        guard let first = c.first else { return "" }
        let back = c.first { abs($0.mean) < 1 && $0.day > 1 }
        var s = "Next morning: " + String(format: "%+.0f", first.mean) + " \(unit) vs your average"
        if first.low < 0 && first.high > 0 { s += " (not clear yet)" }
        if let back { s += ", back to normal by day \(back.day)" }
        return s + "."
    }
}

struct CurveChart: View {
    let points: [CurvePoint]
    let unit: String
    let color: Color

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Mornings after", p.day), yStart: .value("Low", p.low), yEnd: .value("High", p.high))
                    .foregroundStyle(color.opacity(0.15))
                LineMark(x: .value("Mornings after", p.day), y: .value(unit, p.mean))
                    .foregroundStyle(color)
                    .symbol(.circle)
            }
            RuleMark(y: .value("Average", 0))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
        }
        .chartXAxis { AxisMarks(values: points.map(\.day)) { v in AxisValueLabel { Text("Day \(v.as(Int.self) ?? 0)") } } }
        .frame(height: 160)
    }
}

/// The math, for the curious: equation, priors, fitted values and the backtest.
struct ModelDetailView: View {
    let model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "The model", systemImage: "function") {
                    Text("Each morning's recovery is modelled as your average, plus part of yesterday's deviation, plus the effect of workouts in the last 4 days:")
                    Text("y(t) − μ = φ·(y(t−1) − μ) + Σ β(k)·strength(t−k) + Σ γ(k)·other(t−k) + noise")
                        .font(.system(.footnote, design: .monospaced))
                    Text("μ is your average, φ how much of a good or bad morning carries into the next, and β(k), γ(k) how a workout k days ago moves the morning.")
                }
                .font(.subheadline)
                Card(title: "Bayesian fitting", systemImage: "dice") {
                    Text("Every coefficient starts from a prior belief and is updated by your data. With a Normal prior and Normal noise the result is Normal again (a conjugate prior), so the update has a closed form: precision adds up, and the estimate is a precision-weighted blend of prior and data (Bishop 2006, section 3.3).")
                    Text("Priors: φ around 0.5 (± 0.25). Workout effects around 0, with a spread of 10 points the next morning, halving each day after. So an effect has to show up in your data before the model believes it, and older effects fade. The noise level is estimated from your data.")
                    Text("The shaded bands are the 10 to 90% range from 400 draws of the posterior.")
                }
                .font(.subheadline)
                if let r = model.readiness {
                    Card(title: "Your fitted values", systemImage: "slider.horizontal.3") {
                        LabeledContent("Average μ", value: fmt(r.model.mu, 0))
                        LabeledContent("Carry-over φ", value: estimate(r.model, 0, digits: 2))
                        ForEach(1...ReadinessEngine.lags, id: \.self) { k in
                            LabeledContent("Strength, \(k) day\(k == 1 ? "" : "s") ago", value: estimate(r.model, k, digits: 1))
                        }
                        ForEach(1...ReadinessEngine.lags, id: \.self) { k in
                            LabeledContent("Other workout, \(k) day\(k == 1 ? "" : "s") ago", value: estimate(r.model, ReadinessEngine.lags + k, digits: 1))
                        }
                        LabeledContent("Noise", value: "± " + fmt(r.model.posterior.sigma2.squareRoot(), 1))
                        LabeledContent("Mornings used", value: "\(r.model.posterior.n)")
                    }
                    .font(.subheadline)
                    Card(title: "Does it beat a naive guess?", systemImage: "checkmark.seal") {
                        Text("For each of the last 30 mornings the model is refit on the days before and asked to forecast up to 5 mornings ahead. Its average miss is compared with the naive forecast \"same as this morning\". Only days it wins are shown on Today.")
                        HStack {
                            Text("Ahead").frame(width: 60, alignment: .leading)
                            Spacer()
                            Text("model").frame(width: 60, alignment: .trailing)
                            Text("naive").frame(width: 60, alignment: .trailing)
                            Text("better").frame(width: 60, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ForEach(r.skill) { s in
                            HStack {
                                Text("\(s.horizon) day\(s.horizon == 1 ? "" : "s")").frame(width: 60, alignment: .leading)
                                Spacer()
                                Text(fmt(s.modelMAE, 1)).frame(width: 60, alignment: .trailing)
                                Text(fmt(s.naiveMAE, 1)).frame(width: 60, alignment: .trailing)
                                Text(String(format: "%+.0f%%", s.skill * 100))
                                    .foregroundStyle(s.skill > 0 ? Zone.push.color : Zone.recover.color)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Readiness model")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Posterior mean ± one posterior SD.
    private func estimate(_ m: ReadinessModel, _ i: Int, digits: Int) -> String {
        let sd = m.posterior.cov[i][i].squareRoot()
        let f = "%+.\(digits)f ± %.\(digits)f"
        return i == 0 ? String(format: "%.2f ± %.2f", m.posterior.mean[i], sd) : String(format: f, m.posterior.mean[i], sd)
    }
}
