import WidgetKit
import SwiftUI

/// Today's recovery, written by the app after each refresh into the shared App Group. The widget never reads
/// Apple Health itself, so it only shows what the app last computed.
struct RecoveryEntry: TimelineEntry {
    let date: Date
    let score: Double?
    let zone: Int?          // HealthCore.Zone raw value: 0 recover, 1 moderate, 2 push
    let computed: Date?

    static let placeholder = RecoveryEntry(date: .now, score: 68, zone: 2, computed: .now)

    static func load() -> RecoveryEntry {
        let d = UserDefaults(suiteName: SharedKeys.group)
        return RecoveryEntry(date: .now,
                             score: d?.object(forKey: SharedKeys.score) as? Double,
                             zone: d?.object(forKey: SharedKeys.zone) as? Int,
                             computed: d?.object(forKey: SharedKeys.date) as? Date)
    }

    /// Yesterday's score isn't today's: blank it once the day has turned.
    var isToday: Bool { computed.map { Calendar.current.isDateInToday($0) } ?? false }
    var title: String { ["Recover", "Moderate", "Push"][min(max(zone ?? 1, 0), 2)] }
    var color: Color {
        guard isToday, let zone else { return .gray }
        return [Color(red: 0.86, green: 0.27, blue: 0.30), Color(red: 0.93, green: 0.67, blue: 0.18),
                Color(red: 0.20, green: 0.70, blue: 0.47)][min(max(zone, 0), 2)]
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .load())
    }
    /// One entry now and one just after midnight, so a stale score clears at the start of the day.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryEntry>) -> Void) {
        let now = RecoveryEntry.load()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        let next = RecoveryEntry(date: midnight.addingTimeInterval(60), score: now.score, zone: now.zone, computed: now.computed)
        completion(Timeline(entries: [now, next], policy: .after(midnight.addingTimeInterval(3600))))
    }
}

struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryEntry

    private var scoreText: String {
        guard entry.isToday, let s = entry.score else { return "--" }
        return "\(Int(s.rounded()))"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.isToday ? (entry.score ?? 0) : 0, in: 0...100) {
                Image(systemName: "bolt.heart")
            } currentValueLabel: {
                Text(scoreText)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Recovery").font(.headline)
                Text(entry.isToday ? "\(scoreText), \(entry.title.lowercased())" : "Open the app to update")
            }
        case .accessoryInline:
            Text(entry.isToday ? "Recovery \(scoreText), \(entry.title.lowercased())" : "Recovery --")
        default:
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(entry.color.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: entry.isToday ? (entry.score ?? 0) / 100 : 0)
                        .stroke(entry.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(scoreText).font(.system(.title, design: .rounded).weight(.bold))
                }
                .padding(4)
                Text(entry.isToday ? entry.title : "Open the app")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.isToday ? entry.color : .secondary)
            }
        }
    }
}

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedKeys.widgetKind, provider: Provider()) { entry in
            RecoveryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recovery")
        .description("This morning's recovery score and zone.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct HealthWidgets: WidgetBundle {
    var body: some Widget { RecoveryWidget() }
}
