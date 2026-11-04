import Foundation

public struct LiftSet: Sendable, Equatable {
    public let exercise: String
    public let weight: Double      // kg, 0 for bodyweight
    public let reps: Int
    public let isWarmup: Bool
    public let rpe: Double?

    public init(exercise: String, weight: Double, reps: Int, isWarmup: Bool = false, rpe: Double? = nil) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.isWarmup = isWarmup
        self.rpe = rpe
    }
}

/// One logged lifting workout, from a Strong export.
public struct LiftSession: Identifiable, Sendable {
    public let start: Date
    public let duration: TimeInterval?
    public let name: String
    public let sets: [LiftSet]

    public var id: Date { start }
    /// Strong leaves duration out on some rows; one hour is a fair stand-in for matching.
    public var end: Date { start.addingTimeInterval(duration ?? 3600) }
    public var working: [LiftSet] { sets.filter { !$0.isWarmup } }

    /// Exercises in the order they were done.
    public var exercises: [String] {
        var seen = Set<String>()
        return sets.map(\.exercise).filter { seen.insert($0).inserted }
    }

    public init(start: Date, duration: TimeInterval?, name: String, sets: [LiftSet]) {
        self.start = start
        self.duration = duration
        self.name = name
        self.sets = sets
    }
}

public enum WeightUnit: String, Sendable {
    case kg, lbs
    /// International yard and pound agreement (1959): 1 lb = 0.45359237 kg exactly.
    var toKg: Double { self == .kg ? 1 : 0.45359237 }
}

public enum StrongImportError: Error, Equatable {
    case missingColumns([String])
    case noSets
}

/// Reads the CSV that Strong exports (Settings, Export data). One row per set with columns
/// Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE.
/// Columns are matched by name, so older exports with a Weight Unit column and semicolon exports both work.
/// Rows without reps (cardio, timed holds, rest timers) are skipped.
public enum StrongCSV {
    public static func parse(_ text: String, unit: WeightUnit = .kg, timeZone: TimeZone = .current) throws -> [LiftSession] {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows = records(text, delimiter: delimiter)
        guard !rows.isEmpty else { throw StrongImportError.noSets }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let required = ["date", "exercise name", "weight", "reps"]
        let missing = required.filter { column($0) == nil }
        guard missing.isEmpty else { throw StrongImportError.missingColumns(missing) }
        let date = column("date")!, exercise = column("exercise name")!, weight = column("weight")!, reps = column("reps")!
        let name = column("workout name"), duration = column("duration"), order = column("set order"),
            rpe = column("rpe"), unitColumn = column("weight unit")

        let formatters = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss"].map { f in
            let d = DateFormatter()
            d.locale = Locale(identifier: "en_US_POSIX")
            d.timeZone = timeZone
            d.dateFormat = f
            return d
        }
        func field(_ row: [String], _ i: Int?) -> String {
            guard let i, i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }

        var keys: [String] = []
        var grouped: [String: (start: Date, duration: TimeInterval?, name: String, sets: [LiftSet])] = [:]
        for row in rows {
            let r = Int(number(field(row, reps)) ?? 0)
            let dateText = field(row, date)
            guard r > 0, let start = formatters.lazy.compactMap({ $0.date(from: dateText) }).first else { continue }
            let rowUnit = WeightUnit(rawValue: field(row, unitColumn).lowercased()) ?? unit
            let set = LiftSet(exercise: field(row, exercise), weight: max(0, (number(field(row, weight)) ?? 0) * rowUnit.toKg),
                              reps: r, isWarmup: field(row, order).uppercased() == "W", rpe: number(field(row, rpe)))
            let key = dateText + "|" + field(row, name)
            if grouped[key] == nil {
                keys.append(key)
                grouped[key] = (start, parseDuration(field(row, duration)), field(row, name), [])
            }
            grouped[key]!.sets.append(set)
        }
        guard !keys.isEmpty else { throw StrongImportError.noSets }
        return keys.compactMap { grouped[$0] }
            .map { LiftSession(start: $0.start, duration: $0.duration, name: $0.name, sets: $0.sets) }
            .sorted { $0.start > $1.start }   // newest first, like workouts
    }

    /// RFC 4180 records: quoted fields may hold delimiters, doubled quotes and line breaks (Strong notes can).
    static func records(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, pendingQuote = false
        for c in text {
            if quoted {
                if pendingQuote {
                    pendingQuote = false
                    if c == "\"" { field.append(c); continue }
                    quoted = false
                } else if c == "\"" {
                    pendingQuote = true
                    continue
                } else {
                    field.append(c)
                    continue
                }
            }
            if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if row != [""] { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
        }
        row.append(field)
        if row != [""] { rows.append(row) }
        return rows
    }

    /// Accepts a decimal comma, which semicolon exports use.
    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    /// "1h 5m", "45m", "30s" or plain seconds.
    static func parseDuration(_ s: String) -> TimeInterval? {
        if let seconds = Double(s) { return seconds > 0 ? seconds : nil }
        var total = 0.0, digits = ""
        for c in s {
            if c.isNumber || c == "." { digits.append(c); continue }
            guard let v = Double(digits) else { digits = ""; continue }
            switch c {
            case "h": total += v * 3600
            case "m": total += v * 60
            case "s": total += v
            default: break
            }
            digits = ""
        }
        return total > 0 ? total : nil
    }
}

public struct ExerciseProgress: Identifiable, Sendable {
    public let name: String
    /// Best estimated 1RM per session, oldest first.
    public let e1rm: [DailyValue]
    public let sessions: Int
    public let lastDone: Date
    /// Latest e1RM minus the latest one at least 28 days earlier, kg.
    public let change: Double?
    public var current: Double? { e1rm.last?.value }
    public var id: String { name }
}

public struct WeekVolume: Identifiable, Sendable {
    public let weekStart: Date
    public let volumeLoad: Double  // kg
    public let workingSets: Int
    public var id: Date { weekStart }
}

public enum LiftingEngine {
    /// Estimated one-rep max, Epley (1985, Poundage chart, Boyd Epley Workout): weight·(1 + reps/30). Among the more accurate equations for the
    /// bench press, squat and deadlift up to 10 reps (LeSuer et al. 1997, "The accuracy of prediction equations
    /// for estimating 1-RM performance in the bench press, squat, and deadlift", J Strength Cond Res 11(4)).
    /// Above 10 reps the error grows, so those sets give no estimate. A single is its own 1RM.
    public static func e1rm(weight: Double, reps: Int) -> Double? {
        guard weight > 0, (1...10).contains(reps) else { return nil }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// Volume load: Σ weight × reps over working sets, kg. Haff (2010), "Quantifying workloads in resistance
    /// training: a brief review", Professional Strength and Conditioning 19 (UKSCA). Warm-up sets are left out.
    public static func volumeLoad(_ sets: [LiftSet]) -> Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    public static func bestE1rm(_ sets: [LiftSet]) -> Double? {
        sets.filter { !$0.isWarmup }.compactMap { e1rm(weight: $0.weight, reps: $0.reps) }.max()
    }

    /// Per exercise e1RM history, most trained in the last 8 weeks first.
    public static func progress(_ sessions: [LiftSession], endingOn day: Date) -> [ExerciseProgress] {
        let cal = Calendar.current
        let recentStart = cal.date(byAdding: .day, value: -56, to: day)!
        var byExercise: [String: [(date: Date, sets: [LiftSet])]] = [:]
        for s in sessions {
            for name in s.exercises {
                byExercise[name, default: []].append((s.start, s.sets.filter { $0.exercise == name }))
            }
        }
        return byExercise.map { name, done in
            let sorted = done.sorted { $0.date < $1.date }
            let points = sorted.compactMap { d in bestE1rm(d.sets).map { DailyValue(date: cal.startOfDay(for: d.date), value: $0) } }
            var change: Double?
            if let last = points.last, let cutoff = cal.date(byAdding: .day, value: -28, to: last.date),
               let before = points.last(where: { $0.date <= cutoff }) {
                change = last.value - before.value
            }
            return ExerciseProgress(name: name, e1rm: points, sessions: sorted.filter { $0.date >= recentStart }.count,
                                    lastDone: sorted.last!.date, change: change)
        }
        .sorted { ($0.sessions, $0.lastDone) > ($1.sessions, $1.lastDone) }
    }

    /// Volume load and working sets per week (Monday start), oldest first, the last `weeks` weeks.
    public static func weekly(_ sessions: [LiftSession], weeks: Int, endingOn day: Date) -> [WeekVolume] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = Calendar.current.timeZone
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: day)!.start
        return (0..<weeks).reversed().map { back in
            let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek)!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            let sets = sessions.filter { $0.start >= start && $0.start < end }.flatMap(\.working)
            return WeekVolume(weekStart: start, volumeLoad: volumeLoad(sets), workingSets: sets.count)
        }
    }

    /// The logged session that overlaps a watch workout, closest start first. Strong and the watch are started
    /// by hand, so a few minutes of slack either side.
    public static func session(for w: WorkoutSummary, in sessions: [LiftSession]) -> LiftSession? {
        let slack: TimeInterval = 15 * 60
        return sessions
            .filter { $0.start < w.end.addingTimeInterval(slack) && $0.end > w.start.addingTimeInterval(-slack) }
            .min { abs($0.start.timeIntervalSince(w.start)) < abs($1.start.timeIntervalSince(w.start)) }
    }
}
