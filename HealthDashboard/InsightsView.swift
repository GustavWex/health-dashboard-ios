import SwiftUI
import SwiftData
import Charts
import HealthCore

/// Insights as a page, opened from the block at the top of Trends. The report is computed there.
struct InsightsPage: View {
    let model: DashboardModel
    let report: InsightReport?
    let tags: [(day: Date, tags: [String])]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "What moves your numbers", systemImage: "sparkle.magnifyingglass") {
                    if let report {
                        findings(report)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    DisclosureGroup("How this works") {
                        Text("Each habit is compared with your recovery, HRV, resting heart rate, sleep efficiency and how you feel over the next 1 to 3 mornings. Weekday patterns are removed first, and nutrition is compared at equal sleep. Days aren't independent, so the sample size is shrunk for that, and only patterns passing a 10% false discovery rate are shown. Patterns, not proof of cause.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                WeekReportCard(model: model)
                RecoveryCurveCard(model: model)
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The report's inputs, shared by Trends (which computes it) and Ask your data.
    static func compute(_ model: DashboardModel, entries: [JournalEntry]) async -> InsightReport {
        let s = model.snapshot, recovery = model.scoreHistory, days = model.training?.days ?? [], lifts = model.lifts
        let tags = entries.map { (day: $0.day, tags: $0.tags) }, feel = entries.feelSeries
        return await Task.detached(priority: .userInitiated) {
            InsightsEngine.report(s, recovery: recovery, training: days, lifts: lifts, tags: tags, feel: feel)
        }.value
    }

    @ViewBuilder
    private func findings(_ r: InsightReport) -> some View {
        if r.findings.isEmpty {
            Text(r.tested == 0
                 ? "Not enough data yet. Each comparison needs 30 days with both values and at least 15 days on each side."
                 : "No clear patterns yet among \(r.tested) comparisons. More days make smaller effects visible.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(r.findings) { i in
                NavigationLink {
                    InsightDetailView(insight: i, all: r.all, model: model, tags: tags)
                } label: {
                    InsightRow(insight: i)
                }
                .buttonStyle(.plain)
                if i.id != r.findings.last?.id { Divider() }
            }
            Text("\(r.findings.count) of \(r.tested) comparisons pass the bar.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The full-width block at the top of Trends: the strongest pattern, or why there is none yet.
struct InsightsBlock: View {
    let report: InsightReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Insights, all history").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let r = report, !r.findings.isEmpty {
                    Text("\(r.findings.count) pattern\(r.findings.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            if let r = report {
                if let top = r.findings.first {
                    Label(InsightText.headline(top), systemImage: top.helps ? "arrow.up.heart.fill" : "arrow.down.heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(top.helps ? Palette.good : Palette.bad, .primary)
                        .lineLimit(2)
                    Text(InsightText.comparison(top)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text(r.tested == 0 ? "Not enough days yet to look for patterns." : "No clear patterns yet among \(r.tested) comparisons.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .glassCard(12)
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.helps ? "arrow.up.heart.fill" : "arrow.down.heart.fill")
                .foregroundStyle(insight.helps ? Zone.push.color : Zone.recover.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(InsightText.headline(insight)).font(.subheadline.weight(.semibold))
                Text(InsightText.comparison(insight)).font(.subheadline)
                Text(InsightText.stats(insight)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// Plain-language text for an insight. UI copy lives here, the numbers come from HealthCore.
enum InsightText {
    static func value(_ v: Double, _ kind: FeatureKind) -> String {
        switch kind {
        case .clock:
            let m = (Int(v.rounded()) % 1440 + 1440) % 1440
            return String(format: "%02d:%02d", m / 60, m % 60)
        case .kcal: return "\(Int(v.rounded())) kcal"
        case .grams: return "\(Int(v.rounded())) g"
        case .hours: return v.formatted(.number.precision(.fractionLength(1))) + " h"
        case .minutes: return "\(Int(v.rounded())) min"
        case .count: return Int(v.rounded()).formatted()
        case .strain: return v.formatted(.number.precision(.fractionLength(1)))
        case .kg: return "\(Int(v.rounded()).formatted()) kg"
        case .ppm: return "\(Int(v.rounded()).formatted()) ppm"
        case .celsius: return String(format: "%.1f °C", v)
        case .percent: return "\(Int(v.rounded()))%"
        case .lux: return "\(Int(v.rounded()).formatted()) lux"
        case .flag: return v >= 0.5 ? "yes" : "no"
        }
    }

    static func outcome(_ v: Double, _ o: InsightOutcome) -> String {
        "\(Int(v.rounded()))" + (o.unit.isEmpty ? "" : (o.unit == "%" ? "%" : " " + o.unit))
    }

    static func when(_ i: Insight) -> String {
        let start = ["the next morning", "two mornings later", "three mornings later"][min(i.lag, 2)]
        return i.mornings > 1 ? start + ", lasting \(i.mornings) mornings" : start
    }

    static func headline(_ i: Insight) -> String {
        let more = i.r > 0 ? "higher" : "lower"
        if i.feature.kind == .flag {
            return "\(i.feature.name) goes with \(more) \(i.outcome.name.inSentence) \(when(i))"
        }
        let what = i.feature.kind == .clock ? "A later \(i.feature.name.inSentence)" : "More \(i.feature.name.inSentence)"
        return "\(what) goes with \(more) \(i.outcome.name.inSentence) \(when(i))"
    }

    static func comparison(_ i: Insight) -> String {
        let o = i.outcome
        if i.feature.kind == .flag {
            return "\(o.name) \(outcome(i.highMean, o)) on those days vs \(outcome(i.lowMean, o)) otherwise (\(i.highN) vs \(i.lowN) days)"
        }
        let t = value(i.threshold ?? 0, i.feature.kind)
        let clock = i.feature.kind == .clock
        let (low, high) = clock ? ("before \(t)", "later") : ("under \(t)", "more")
        return "\(i.feature.name) \(low)\(context(i, low: true)): \(o.name.inSentence) \(outcome(i.lowMean, o)). "
            + "\(high.prefix(1).uppercased() + high.dropFirst())\(context(i, low: false)): \(outcome(i.highMean, o)). (\(i.lowN) and \(i.highN) days)"
    }

    /// ", waking around 09:10" when the feature carries a companion measure.
    static func context(_ i: Insight, low: Bool) -> String {
        guard let ctx = i.feature.context, let v = low ? i.lowContext : i.highContext else { return "" }
        return ", \(ctx.name) around \(value(v, ctx.kind))"
    }

    static func stats(_ i: Insight) -> String {
        let r = { (v: Double) in String(format: "%+.2f", v) }
        return "r \(r(i.r)), 95% range \(r(i.ci.lowerBound)) to \(r(i.ci.upperBound)), \(i.n) days"
    }
}

struct InsightDetailView: View {
    let insight: Insight
    let all: [Insight]
    let model: DashboardModel
    let tags: [(day: Date, tags: [String])]

    private var pairs: [InsightsEngine.Pair] {
        InsightsEngine.pairs(insight.feature, insight.outcome, lag: insight.lag,
                             sleepHours: model.snapshot.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) })
    }
    private var lags: [Insight] {
        all.filter { $0.feature.id == insight.feature.id && $0.outcome.id == insight.outcome.id }.sorted { $0.lag < $1.lag }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: insight.outcome.name, systemImage: insight.helps ? "arrow.up.heart" : "arrow.down.heart") {
                    Text(InsightText.headline(insight)).font(.headline)
                    Text(InsightText.comparison(insight)).font(.subheadline)
                    Chart {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { _, p in
                            PointMark(x: .value(insight.feature.name, p.x), y: .value(insight.outcome.name, p.y))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .symbolSize(24)
                        }
                        if let t = insight.threshold {
                            RuleMark(x: .value("Split", t))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        }
                    }
                    .chartXScale(domain: .automatic(includesZero: false))
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks { v in
                            AxisGridLine()
                            AxisValueLabel { if let d = v.as(Double.self) { Text(InsightText.value(d, insight.feature.kind)) } }
                        }
                    }
                    .frame(height: 220)
                    Text("Each dot is one day: \(insight.feature.name.inSentence) against \(insight.outcome.name.inSentence) \(InsightText.when(insight)).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Card(title: "Something to try", systemImage: "flask") {
                    Text(InsightAction.suggestion(insight)).font(.subheadline)
                }
                Card(title: "By delay", systemImage: "clock.arrow.circlepath") {
                    ForEach(lags) { l in
                        HStack {
                            Text(["Next morning", "2 mornings later", "3 mornings later"][min(l.lag, 2)])
                            Spacer()
                            Text(String(format: "r %+.2f", l.r)).monospacedDigit()
                            Text(l.q < InsightsEngine.fdr ? "clear" : "unclear")
                                .foregroundStyle(l.q < InsightsEngine.fdr ? .primary : .secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
                Card(title: "The numbers", systemImage: "number") {
                    LabeledContent("Days compared", value: "\(insight.n)")
                    LabeledContent("Effective days", value: "\(Int(insight.effectiveN.rounded()))")
                    LabeledContent("Correlation", value: String(format: "%+.2f", insight.r))
                    LabeledContent("95% range", value: String(format: "%+.2f to %+.2f", insight.ci.lowerBound, insight.ci.upperBound))
                    LabeledContent("False discovery rate", value: String(format: "%.1f%%", insight.q * 100))
                    Text(insight.feature.controlForSleep
                         ? "Weekday and that night's sleep are held fixed."
                         : "Weekday patterns are held fixed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle(insight.feature.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// This week against the 4 weeks before, for the main numbers.
struct WeekReportCard: View {
    let model: DashboardModel

    private struct Row: Identifiable {
        let name: String
        let digits: Int
        let unit: String
        let higherIsBetter: Bool?
        let c: WeekComparison
        var id: String { name }
    }

    private var rows: [Row] {
        let s = model.snapshot
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let logged = s.dietaryEnergy.filter { $0.value > 300 }
        let loggedDays = Set(logged.map(\.date))
        return [
            Row(name: "Recovery", digits: 0, unit: "", higherIsBetter: true, c: WeeklyReport.compare(model.scoreHistory, endingOn: today)),
            Row(name: "HRV", digits: 0, unit: " ms", higherIsBetter: true, c: WeeklyReport.compare(s.hrv, endingOn: today)),
            Row(name: "Resting HR", digits: 0, unit: " bpm", higherIsBetter: false, c: WeeklyReport.compare(s.restingHR, endingOn: today)),
            Row(name: "Sleep", digits: 1, unit: " h", higherIsBetter: true,
                c: WeeklyReport.compare(s.sleep.map { DailyValue(date: $0.date, value: $0.asleep / 3600) }, endingOn: today)),
            Row(name: "Day strain", digits: 1, unit: "", higherIsBetter: nil,
                c: WeeklyReport.compare((model.training?.days ?? []).compactMap { d in d.strain.map { DailyValue(date: d.date, value: $0) } }, endingOn: today)),
            Row(name: "Calories", digits: 0, unit: " kcal", higherIsBetter: nil, c: WeeklyReport.compare(logged, endingOn: yesterday)),
            Row(name: "Protein", digits: 0, unit: " g", higherIsBetter: true,
                c: WeeklyReport.compare(s.protein.filter { loggedDays.contains($0.date) }, endingOn: yesterday)),
            Row(name: "Steps", digits: 0, unit: "", higherIsBetter: nil, c: WeeklyReport.compare(s.steps, endingOn: yesterday)),
        ].filter { $0.c.thisWeek != nil }
    }

    var body: some View {
        Card(title: "This week vs your usual", systemImage: "calendar") {
            HStack {
                Spacer()
                Text("week").frame(width: 80, alignment: .trailing)
                Text("usual").frame(width: 80, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(rows) { r in
                HStack {
                    Text(r.name)
                    Spacer()
                    Text(fmt(r.c.thisWeek, r.digits, r.unit))
                        .monospacedDigit()
                        .foregroundStyle(color(r))
                        .frame(width: 80, alignment: .trailing)
                    Text(fmt(r.c.usual, r.digits, r.unit))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.subheadline)
            }
            Text("Last 7 days against the 4 weeks before. Food and steps end yesterday, since today isn't complete.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Green or red only when the change is more than 5% and the direction has a clear better side.
    private func color(_ r: Row) -> Color {
        guard let better = r.higherIsBetter, let t = r.c.thisWeek, let u = r.c.usual, u != 0, abs(t - u) / abs(u) > 0.05 else { return .primary }
        return (t > u) == better ? Zone.push.color : Zone.recover.color
    }
}

extension String {
    /// Lowercase for the middle of a sentence, keeping abbreviations like HR, HRV and CO2 as they are.
    var inSentence: String {
        split(separator: " ", omittingEmptySubsequences: false).map { w in
            w.count > 1 && w.allSatisfy { $0.isUppercase || $0.isNumber } ? String(w) : w.lowercased()
        }.joined(separator: " ")
    }
}
