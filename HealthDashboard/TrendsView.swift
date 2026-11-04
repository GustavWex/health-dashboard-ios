import SwiftUI
import SwiftData
import Charts
import HealthCore

enum TrendRange: Int, CaseIterable {
    case week = 7, month = 30, quarter = 90, year = 365, all = 7300

    var label: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        case .year: "1Y"
        case .all: "All"
        }
    }

    var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "1 year"
        case .all: "all time"
        }
    }

    /// Daily points get crowded past about 4 months, so longer ranges show weekly averages.
    var weekly: Bool { rawValue > 120 }

    /// Points in range, as weekly averages for long ranges.
    func shown(_ pts: [DailyValue], from day: Date = Calendar.current.startOfDay(for: .now)) -> [DailyValue] {
        let r = pts.recent(days: rawValue, from: day)
        return weekly ? Weekly.means(r) : r
    }
}

/// Trends as small multiples: the same small chart for every metric, on the same time axis, so shapes can be
/// compared at a glance (Tufte). Tap one for its full chart (overview, then detail).
struct TrendsView: View {
    let model: DashboardModel
    @AppStorage("trendRange") private var rangeRaw = TrendRange.month.rawValue
    @Query private var entries: [JournalEntry]
    @State private var report: InsightReport?

    private var insightsKey: String {
        "\(model.refreshCount)|\(entries.map { $0.tags.count + ($0.feel ?? 0) * 100 }.reduce(0, +))|\(entries.count)"
    }

    private var range: TrendRange { TrendRange(rawValue: rangeRaw) ?? .month }

    /// One shared x domain for every tile. "All" starts at the oldest point any metric has.
    private var domain: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let earliest = TrendMetric.allCases.compactMap { range.shown($0.values(model)).first?.date }.min() ?? today
        let start = range == .all ? earliest : Calendar.current.date(byAdding: .day, value: -(range.rawValue - 1), to: today)!
        return start...today
    }

    private var metrics: [TrendMetric] { TrendMetric.recommended.filter { !range.shown($0.values(model)).isEmpty } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Range", selection: $rangeRaw) {
                        ForEach(TrendRange.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    NavigationLink {
                        InsightsPage(model: model, report: report, tags: entries.map { (day: $0.day, tags: $0.tags) })
                    } label: {
                        InsightsBlock(report: report)
                    }
                    .buttonStyle(.plain)
                    if !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(metrics) { m in
                            NavigationLink {
                                MetricDetailView(model: model, metric: m, range: range)
                            } label: {
                                SmallMultiple(metric: m, points: range.shown(m.values(model)), domain: domain, range: range)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(AmbientBackground())
            .navigationTitle("Trends")
            .toolbar {
                NavigationLink { AskView(model: model) } label: { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
            }
            .refreshable { await model.refresh() }
            .task(id: insightsKey) { report = await InsightsPage.compute(model, entries: entries) }
        }
    }

    private var note: String {
        var parts: [String] = []
        if range.weekly { parts.append("Weekly averages") }
        let history = UserDefaults.standard.object(forKey: AppSettings.historyDaysKey) as? Int ?? AppSettings.defaultHistoryDays
        if range.rawValue > history {
            let label = AppSettings.historyOptions.first { $0.days == history }?.label ?? "\(history) days"
            parts.append(parts.isEmpty ? "Loading \(label) of history; change it in Settings" : "loading \(label) of history; change it in Settings")
        }
        return parts.isEmpty ? "" : parts.joined(separator: ", ") + "."
    }
}

/// One small multiple: name, headline value, change over the range, and a bare line on the shared time axis.
struct SmallMultiple: View {
    let metric: TrendMetric
    let points: [DailyValue]
    let domain: ClosedRange<Date>
    let range: TrendRange
    /// Today's tiles: the latest day's value against the range average, since Today is about this day.
    var latest = false

    /// Latest value for levels (weight), 7-day mean for daily measures (HRV, sleep); always the latest on Today.
    private var headline: Double? {
        latest || metric.isLevel ? points.last?.value : Stats.mean(points.suffix(range.weekly ? 1 : 7).map(\.value))
    }
    /// Like with like: first value against latest for levels, first 7-day mean against last for daily measures.
    private var change: Double? {
        if latest {
            guard let last = points.last?.value, let avg = Stats.mean(points.map(\.value)), points.count > 2 else { return nil }
            return last - avg
        }
        let n = metric.isLevel || range.weekly ? 1 : 7
        guard points.count >= 2 * n, let first = Stats.mean(points.prefix(n).map(\.value)), let last = headline else { return nil }
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.format(headline)).font(.headline).monospacedDigit()
                if let c = change {
                    Text(String(format: "%+.\(metric.digits)f", c))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(color(c))
                }
            }
            Chart(points) { p in
                LineMark(x: .value("Day", p.date, unit: .day), y: .value(metric.name, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(metric.color)
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 44)
            Text(latest ? "latest, vs 30-day average" : (metric.isLevel ? "latest, change over range" : (range.weekly ? "last week, change over range" : "7-day average, change over range")))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(12)
    }

    /// Green or red only when the metric has a clear better direction; otherwise neutral.
    private func color(_ c: Double) -> Color {
        guard let better = metric.higherIsBetter, abs(c) > 0 else { return .secondary }
        return (c > 0) == better ? Zone.push.color : Zone.recover.color
    }
}

/// The detail behind a tile: the full chart with axes, a few summary numbers, and week by week.
struct MetricDetailView: View {
    let model: DashboardModel
    let metric: TrendMetric
    let range: TrendRange
    @State private var selected: Date?

    private var points: [DailyValue] { range.shown(metric.values(model)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "\(metric.name), \(range.title)", systemImage: "chart.xyaxis.line") {
                    chart
                    let v = points.map(\.value)
                    HStack {
                        MetricTile(label: "Average", value: metric.format(Stats.mean(v)))
                        MetricTile(label: "Lowest", value: metric.format(v.min()))
                        MetricTile(label: "Highest", value: metric.format(v.max()))
                    }
                    if range.weekly {
                        Text("Weekly averages.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    WeekByWeekView(model: model, metrics: [metric])
                } label: {
                    HStack {
                        Text("Week by week")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .padding()
                    .glassCard(12)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var chart: some View {
        switch metric {
        case .recovery: recoveryChart
        case .weight: weightChart
        case .sleep: BarTrend(points: points, unit: "h", color: metric.color, rule: model.sleep?.needHours)
        default: LineTrend(points: points, unit: metric.unit, color: metric.color, baseline: Stats.mean(points.map(\.value)))
        }
    }

    /// Recovery with your personal zone cutoffs drawn in and labelled where they are.
    private var recoveryChart: some View {
        Chart {
            if let r = model.recovery {
                RuleMark(y: .value("Recover below", r.low))
                    .foregroundStyle(Zone.recover.color)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) { Text("recover").font(.caption2).foregroundStyle(Zone.recover.color) }
                RuleMark(y: .value("Push from", r.high))
                    .foregroundStyle(Zone.push.color)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) { Text("push").font(.caption2).foregroundStyle(Zone.push.color) }
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date, unit: .day), y: .value("Score", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(metric.color)
            }
            if let pick = ChartSelection.nearest(points, to: selected) {
                RuleMark(x: .value("Selected", pick.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartSelection.callout(pick, unit: "")
                    }
                PointMark(x: .value("Day", pick.date, unit: .day), y: .value("Score", pick.value))
                    .foregroundStyle(metric.color)
            }
        }
        .chartXSelection(value: $selected)
        .chartYScale(domain: 0...100)
        .frame(height: 200)
        .padding(.top, 24)
    }

    /// Weigh-ins as dots with the smoothed trend as a line.
    private var weightChart: some View {
        let trend = range.shown(model.bodyComp?.trend ?? [])
        return Chart {
            ForEach(points) { p in
                PointMark(x: .value("Day", p.date, unit: .day), y: .value("kg", p.value))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .symbolSize(18)
            }
            ForEach(trend) { p in
                LineMark(x: .value("Day", p.date, unit: .day), y: .value("Trend", p.value))
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.monotone)
            }
            // The weigh-in itself, with the trend that day in the callout
            if let pick = ChartSelection.nearest(points, to: selected) {
                RuleMark(x: .value("Selected", pick.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            ChartSelection.callout(pick, unit: "kg")
                            if let t = ChartSelection.nearest(trend, to: pick.date) {
                                Text("trend " + ChartSelection.valueText(t.value, unit: "kg")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                PointMark(x: .value("Day", pick.date, unit: .day), y: .value("kg", pick.value))
                    .foregroundStyle(metric.color)
            }
        }
        .chartXSelection(value: $selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 200)
        .padding(.top, 24)
    }
}
