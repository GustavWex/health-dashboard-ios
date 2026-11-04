import WidgetKit
import SwiftUI

/// Watch face complications from the numbers the iPhone sends. Three: the day (status colour with recovery),
/// sleep and strain, in the circular, corner, rectangular and inline slots watch faces offer.
struct DayEntry: TimelineEntry {
    let date: Date
    let day: WatchDay
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now, day: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now, day: context.isPreview ? .placeholder : .load()))
    }
    /// Now, and just after midnight so yesterday's numbers clear at the start of the day.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let day = WatchDay.load()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [DayEntry(date: .now, day: day), DayEntry(date: midnight.addingTimeInterval(60), day: day)],
                            policy: .after(midnight.addingTimeInterval(3600))))
    }
}

// MARK: Day

struct DayComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let day: WatchDay

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: day.isToday ? (day.score ?? 0) : 0, in: 0...100) {
                Image(systemName: "heart.fill")
            } currentValueLabel: {
                Text(day.text(day.score, 0))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(day.statusColor)
        case .accessoryCorner:
            Text(day.text(day.score, 0))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(day.statusColor)
                .widgetLabel {
                    Gauge(value: day.isToday ? (day.score ?? 0) : 0, in: 0...100) { Text("Recovery") }
                        .tint(day.statusColor)
                }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Circle().fill(day.statusColor).frame(width: 8, height: 8)
                    Text(day.statusWord).font(.headline)
                }
                Text("Recovery \(day.text(day.score, 0))").font(.caption)
                Text("Sleep \(day.text(day.sleep, 0)) · Strain \(day.text(day.strain, 1))").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(day.isToday ? "\(day.statusWord) · recovery \(day.text(day.score, 0))" : "Health --")
        }
    }
}

struct DayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedKeys.dayKind, provider: DayProvider()) { entry in
            DayComplicationView(day: entry.day).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Day")
        .description("Good, steady or easy, with this morning's recovery.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Sleep and strain

struct GaugeComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let day: WatchDay
    let value: Double?
    let maxValue: Double
    let digits: Int
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        switch family {
        case .accessoryCorner:
            Text(day.text(value, digits))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .widgetLabel { Gauge(value: day.isToday ? (value ?? 0) : 0, in: 0...maxValue) { Text(label) }.tint(color) }
        case .accessoryInline:
            Text("\(label) \(day.text(value, digits))")
        default:
            Gauge(value: day.isToday ? (value ?? 0) : 0, in: 0...maxValue) {
                Image(systemName: symbol)
            } currentValueLabel: {
                Text(day.text(value, digits))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(color)
        }
    }
}

struct SleepComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedKeys.sleepKind, provider: DayProvider()) { entry in
            GaugeComplicationView(day: entry.day, value: entry.day.sleep, maxValue: 100, digits: 0, label: "Sleep",
                                  symbol: "bed.double.fill", color: WatchDay.sleepColor)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Sleep")
        .description("Last night's sleep score.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct StrainComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedKeys.strainKind, provider: DayProvider()) { entry in
            GaugeComplicationView(day: entry.day, value: entry.day.strain, maxValue: 21, digits: 1, label: "Strain",
                                  symbol: "flame.fill", color: WatchDay.strainColor)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Strain")
        .description("Today's strain out of 21.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct HealthComplications: WidgetBundle {
    var body: some Widget {
        DayComplication()
        SleepComplication()
        StrainComplication()
    }
}
