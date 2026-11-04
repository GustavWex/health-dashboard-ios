import Foundation

public struct TagImpact: Identifiable, Sendable {
    public let tag: String
    public let delta: Double     // recovery points vs days without the tag
    public let count: Int
    public var id: String { tag }
}

public enum ImpactEngine {
    /// Difference in mean next-morning recovery between tagged days and all other days (Athlytic journal).
    /// Plain difference of means for now: no weekday deconfounding or intervals until the Phase 5 insights engine.
    public static func analyze(entries: [(day: Date, tags: [String])], scores: [DailyValue]) -> [TagImpact] {
        let cal = Calendar.current
        let allTags = Set(entries.flatMap { $0.tags })
        return allTags.compactMap { tag -> TagImpact? in
            let taggedDays = entries.filter { $0.tags.contains(tag) }.map { cal.startOfDay(for: $0.day) }
            let with = taggedDays.compactMap { scores.value(on: cal.date(byAdding: .day, value: 1, to: $0)!) }
            let taggedSet = Set(taggedDays)
            let without = scores
                .filter { !taggedSet.contains(cal.date(byAdding: .day, value: -1, to: $0.date)!) }
                .map(\.value)
            guard with.count >= 3, without.count >= 3,
                  let a = Stats.mean(with), let b = Stats.mean(without) else { return nil }
            return TagImpact(tag: tag, delta: a - b, count: with.count)
        }
        .sorted { abs($0.delta) > abs($1.delta) }
    }
}
