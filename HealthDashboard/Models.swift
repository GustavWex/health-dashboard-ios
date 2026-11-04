import Foundation
import SwiftData
import HealthCore

/// Journal tags for a given day, stored on device with SwiftData.
@Model
final class JournalEntry {
    @Attribute(.unique) var day: Date
    var tags: [String]
    /// Morning check-in, 1 (drained) to 5 (great), for the morning of `day`. Added later, so optional.
    var feel: Int? = nil

    init(day: Date, tags: [String] = []) {
        self.day = day
        self.tags = tags
    }
}

enum JournalTags {
    static let all = [
        "Alcohol", "Caffeine after 15", "Late heavy meal", "Stressful day",
        "Exam or deadline", "Screens in bed", "Sauna", "Hard leg day",
        "Feeling sick", "Late night out"
    ]
}

extension Array where Element == JournalEntry {
    /// Morning ratings as a daily series, keyed by the morning.
    var feelSeries: [DailyValue] { compactMap { e in e.feel.map { DailyValue(date: e.day, value: Double($0)) } }.sorted { $0.date < $1.date } }
}
