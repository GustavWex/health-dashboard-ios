import Foundation

/// One value per calendar day. `date` is always the start of that day.
public struct DailyValue: Identifiable, Hashable, Sendable {
    public let date: Date
    public let value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// One night of sleep, keyed by the day you woke up.
public struct SleepNight: Identifiable, Sendable {
    public let date: Date
    public let start: Date
    public let end: Date
    public let asleep: TimeInterval
    public let deep: TimeInterval
    public let rem: TimeInterval
    public let core: TimeInterval
    public let awake: TimeInterval
    /// Separate wake bouts inside the night. With total sleep and consistency, the most usable signal:
    /// watch stage percentages are too rough to interpret on their own.
    public let awakenings: Int
    /// Wake after sleep onset: total wake time between falling asleep and the final wake-up.
    public let waso: TimeInterval
    /// The night's samples from the chosen source, oldest first, for drawing a hypnogram.
    public let stages: [StageInterval]
    public var id: Date { date }

    public init(date: Date, start: Date, end: Date, asleep: TimeInterval,
                deep: TimeInterval, rem: TimeInterval, core: TimeInterval, awake: TimeInterval, awakenings: Int = 0,
                waso: TimeInterval = 0, stages: [StageInterval] = []) {
        self.date = date
        self.start = start
        self.end = end
        self.asleep = asleep
        self.deep = deep
        self.rem = rem
        self.core = core
        self.awake = awake
        self.awakenings = awakenings
        self.waso = waso
        self.stages = stages
    }

    /// Intervals spent asleep. Falls back to the whole night when no stage samples were kept.
    public var asleepIntervals: [DateInterval] {
        let asleep = stages.filter { $0.stage != .awake && $0.stage != .inBed }
        return asleep.isEmpty ? [DateInterval(start: start, end: end)] : asleep.map { DateInterval(start: $0.start, end: $0.end) }
    }

    public var efficiency: Double {
        let total = asleep + awake
        return total > 0 ? asleep / total : 0
    }
}

public struct StageInterval: Sendable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A daytime nap, kept apart from the night so it doesn't inflate night totals.
public struct Nap: Identifiable, Sendable {
    public let date: Date        // day the nap belongs to
    public let start: Date
    public let end: Date
    public let asleep: TimeInterval
    public var id: Date { start }

    public init(date: Date, start: Date, end: Date, asleep: TimeInterval) {
        self.date = date
        self.start = start
        self.end = end
        self.asleep = asleep
    }
}

/// One timestamped sample, stripped of HealthKit types.
public struct Reading: Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public enum Sex: Sendable {
    case male, female
}

/// Characteristics from Apple Health. Used for HRmax, TRIMP coefficients and BMR.
public struct Profile: Sendable {
    public var birthDate: Date?
    public var sex: Sex?
    public var height: Double?          // m, latest from Apple Health

    public init(birthDate: Date? = nil, sex: Sex? = nil, height: Double? = nil) {
        self.birthDate = birthDate
        self.sex = sex
        self.height = height
    }

    public func age(on day: Date) -> Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: day).year
    }
}

public struct WorkoutSummary: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let duration: TimeInterval
    public let name: String
    public let isStrength: Bool
    public let energy: Double?
    /// Filled by `TrainingEngine.enrich` from the workout's heart rate samples.
    public var heartRate: WorkoutHeartRate?
    /// Apple's effort rating, 1 to 10 (iOS 18): your own rating if you gave one, else the watch's estimate.
    public var effort: Double?
    public var effortIsEstimate = false
    /// Heart rate drop in the first minute after the workout, from Apple's cardio recovery samples, bpm.
    public var hrRecovery: Double?

    public var end: Date { start.addingTimeInterval(duration) }

    public init(id: UUID, start: Date, duration: TimeInterval, name: String, isStrength: Bool, energy: Double?) {
        self.id = id
        self.start = start
        self.duration = duration
        self.name = name
        self.isStrength = isStrength
        self.energy = energy
    }
}

/// Everything pulled from Apple Health in one refresh. Plain values, so it doesn't care where the data came from.
public struct HealthSnapshot: Sendable {
    public var hrv: [DailyValue] = []            // overnight SDNN, ms
    public var restingHR: [DailyValue] = []      // bpm
    public var respiratoryRate: [DailyValue] = [] // overnight, breaths per minute
    public var wristTemp: [DailyValue] = []      // °C
    public var oxygenSaturation: [DailyValue] = [] // overnight, fraction 0-1
    public var sleep: [SleepNight] = []
    public var naps: [Nap] = []
    public var sleepingHR: [DailyValue] = []       // mean heart rate while asleep, bpm
    public var breathingDisturbances: [DailyValue] = [] // Apple's nightly breathing disturbances, newer watches only
    /// Raw readings during the most recent nights, for the per-night charts. Not the full history.
    public var nightHeartRate: [Reading] = []
    public var nightRespiratory: [Reading] = []
    public var nightHRV: [Reading] = []
    public var activeEnergy: [DailyValue] = []   // kcal
    public var basalEnergy: [DailyValue] = []    // kcal
    public var steps: [DailyValue] = []
    public var weight: [DailyValue] = []         // kg
    public var bodyFat: [DailyValue] = []        // fraction 0-1
    public var leanMass: [DailyValue] = []       // kg
    // From the Withings API (Apple Health has no types for these)
    public var muscleMass: [DailyValue] = []     // kg
    public var bodyWater: [DailyValue] = []      // kg
    public var boneMass: [DailyValue] = []       // kg
    public var visceralFat: [DailyValue] = []    // Withings index, no unit
    public var bmr: [DailyValue] = []            // kcal/day, Withings estimate
    public var metabolicAge: [DailyValue] = []   // years, Withings estimate
    public var dietaryEnergy: [DailyValue] = []  // kcal
    public var protein: [DailyValue] = []        // g
    public var fat: [DailyValue] = []            // g
    public var carbs: [DailyValue] = []          // g
    public var sugar: [DailyValue] = []          // g, total sugar: Health has no added sugar type
    public var fiber: [DailyValue] = []          // g
    /// Micronutrients and limits for diet quality, daily totals; whichever the food app writes.
    public var micronutrients: [Micronutrient: [DailyValue]] = [:]
    /// Energy samples with the time they were logged, for meal timing. Recent days only.
    public var foodLog: [Reading] = []           // kcal
    public var workouts: [WorkoutSummary] = []   // newest first
    /// Bedroom monitor samples (CO2, temperature, humidity, light), imported from its exports.
    public var room: [RoomReading] = []
    public var profile = Profile()

    public init(hrv: [DailyValue] = [], restingHR: [DailyValue] = [], respiratoryRate: [DailyValue] = [],
                wristTemp: [DailyValue] = [], oxygenSaturation: [DailyValue] = [], sleep: [SleepNight] = [],
                naps: [Nap] = [], sleepingHR: [DailyValue] = [], breathingDisturbances: [DailyValue] = [],
                nightHeartRate: [Reading] = [], nightRespiratory: [Reading] = [], nightHRV: [Reading] = [],
                activeEnergy: [DailyValue] = [],
                basalEnergy: [DailyValue] = [], steps: [DailyValue] = [], weight: [DailyValue] = [],
                bodyFat: [DailyValue] = [], leanMass: [DailyValue] = [], dietaryEnergy: [DailyValue] = [],
                protein: [DailyValue] = [], workouts: [WorkoutSummary] = [], profile: Profile = Profile()) {
        self.hrv = hrv
        self.restingHR = restingHR
        self.respiratoryRate = respiratoryRate
        self.wristTemp = wristTemp
        self.oxygenSaturation = oxygenSaturation
        self.sleep = sleep
        self.naps = naps
        self.sleepingHR = sleepingHR
        self.breathingDisturbances = breathingDisturbances
        self.nightHeartRate = nightHeartRate
        self.nightRespiratory = nightRespiratory
        self.nightHRV = nightHRV
        self.activeEnergy = activeEnergy
        self.basalEnergy = basalEnergy
        self.steps = steps
        self.weight = weight
        self.bodyFat = bodyFat
        self.leanMass = leanMass
        self.dietaryEnergy = dietaryEnergy
        self.protein = protein
        self.workouts = workouts
        self.profile = profile
    }
}

/// The arrays below are always sorted by date, oldest first, with at most one value per day.
extension Array where Element == DailyValue {
    /// Binary search, so lookups stay fast on multi-year histories.
    public func value(on day: Date) -> Double? {
        let target = Calendar.current.startOfDay(for: day)
        var lo = 0, hi = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = Calendar.current.startOfDay(for: self[mid].date)
            if d == target { return self[mid].value }
            if d < target { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// Values from the `days` days strictly before `day`.
    public func baseline(before day: Date, days: Int) -> [Double] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: day)!
        return filter { $0.date >= start && $0.date < day }.map(\.value)
    }

    /// Points from the last `days` days, including `day`.
    public func recent(days: Int, from day: Date = Calendar.current.startOfDay(for: .now)) -> [DailyValue] {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: day)!
        return filter { $0.date >= start && $0.date <= day }
    }
}

public enum Daily {
    /// First reading of each calendar day. Used for weigh-ins: the morning reading has the most consistent hydration.
    public static func first(_ readings: [Reading]) -> [DailyValue] {
        let cal = Calendar.current
        var out: [DailyValue] = []
        for r in readings.sorted(by: { $0.date < $1.date }) {
            let day = cal.startOfDay(for: r.date)
            if out.last?.date != day { out.append(DailyValue(date: day, value: r.value)) }
        }
        return out
    }
}

/// Every nutrition type Apple Health stores beyond the macros already in the snapshot (energy, protein, fat,
/// carbs, sugar, fiber), for the food score.
public enum Micronutrient: String, CaseIterable, Sendable {
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK, thiamin, riboflavin, niacin, vitaminB6, folate, vitaminB12,
         biotin, pantothenicAcid, calcium, iron, phosphorus, iodine, magnesium, zinc, selenium, copper, manganese,
         chromium, molybdenum, chloride, potassium, sodium, saturatedFat, monounsaturatedFat, polyunsaturatedFat,
         cholesterol, caffeine, water
}
