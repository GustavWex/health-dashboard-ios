#if DEBUG
import Foundation

/// Deterministic synthetic data for the Simulator and previews, where HealthKit has nothing to read.
/// Shaped like a typical lifter's routine: lifting every other day, frequent afternoon naps, slow lean gain. Lifting dips next-morning HRV and raises resting HR; about 1 night in 15 is a rough one.
public enum MockData {
    public static func snapshot(days: Int = 180, endingOn today: Date = Calendar.current.startOfDay(for: .now),
                                seed: UInt64 = 42) -> HealthSnapshot {
        let cal = Calendar.current
        var rng = SplitMix64(seed: seed)
        var s = HealthSnapshot()
        s.profile = Profile(birthDate: cal.date(byAdding: .year, value: -21, to: today), sex: .male, height: 1.80)
        var segments: [SleepSegment] = []
        var sleepingHR: [Date: Double] = [:]

        for back in (0..<days).reversed() {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let yesterday = cal.date(byAdding: .day, value: -1, to: day)!
            let lifts = back % 2 == 0
            let liftedYesterday = !lifts
            let runs = !lifts && cal.component(.weekday, from: day) == 7 && rng.uniform() < 0.5
            let rough = rng.uniform() < 1.0 / 15

            // Morning readings for this day, after last night's sleep
            let hrv = exp(log(58) + 0.12 * rng.normal()) * (liftedYesterday ? 0.92 : 1) * (rough ? 0.8 : 1)
            let rhr = 51 + 1.5 * rng.normal() + (liftedYesterday ? 2 : 0) + (rough ? 3 : 0)
            s.hrv.append(DailyValue(date: day, value: hrv))
            s.restingHR.append(DailyValue(date: day, value: rhr))
            s.respiratoryRate.append(DailyValue(date: day, value: 14.5 + 0.4 * rng.normal()))
            s.wristTemp.append(DailyValue(date: day, value: 35.2 + 0.15 * rng.normal()))
            s.oxygenSaturation.append(DailyValue(date: day, value: min(1, 0.965 + 0.008 * rng.normal())))

            let hours = max(4.5, 7.4 + 0.6 * rng.normal() - (rough ? 1 : 0))
            let bedtime = cal.date(bySettingHour: 23, minute: 15, second: 0, of: yesterday)!
                .addingTimeInterval(35 * 60 * rng.normal())
            segments += night(from: bedtime, hours: hours, rough: rough, rng: &rng)
            sleepingHR[day] = rhr + 2 + rng.normal()
            if rng.uniform() < 0.75 {
                let napStart = cal.date(bySettingHour: 15, minute: 30, second: 0, of: day)!
                    .addingTimeInterval(45 * 60 * rng.normal())
                let napLength = (20 + 15 * rng.uniform()) * 60
                segments.append(SleepSegment(start: napStart, end: napStart.addingTimeInterval(napLength), stage: .core, fromWatch: true))
            }

            // Daytime values
            let active = 450 + 120 * rng.normal() + (lifts ? 300 : 0) + (runs ? 350 : 0)
            s.activeEnergy.append(DailyValue(date: day, value: max(80, active)))
            s.basalEnergy.append(DailyValue(date: day, value: 1780 + 30 * rng.normal()))
            s.steps.append(DailyValue(date: day, value: max(1500, 8500 + 2500 * rng.normal())))

            // Gain of about 0.25 kg per week, the plan's target; weigh-in on most mornings
            let elapsed = Double(days - 1 - back)
            let trueWeight = 65 - 0.25 / 7 * Double(back)   // reaches 65 kg today
            if rng.uniform() < 0.85 {
                let fat = 0.155 - 0.00002 * elapsed + 0.008 * rng.normal()
                let weight = trueWeight + 0.4 * rng.normal()
                s.weight.append(DailyValue(date: day, value: weight))
                s.bodyFat.append(DailyValue(date: day, value: fat))
                s.leanMass.append(DailyValue(date: day, value: weight * (1 - fat)))
                s.muscleMass.append(DailyValue(date: day, value: weight * (1 - fat) * 0.94))
                s.bodyWater.append(DailyValue(date: day, value: weight * (1 - fat) * 0.73))
                s.boneMass.append(DailyValue(date: day, value: weight * (1 - fat) * 0.05))
                s.visceralFat.append(DailyValue(date: day, value: 3))
            }
            if rng.uniform() < 0.8 {
                let kcal = 2700 + 300 * rng.normal()
                s.dietaryEnergy.append(DailyValue(date: day, value: kcal))
                s.protein.append(DailyValue(date: day, value: 135 + 15 * rng.normal()))
                s.fat.append(DailyValue(date: day, value: 85 + 12 * rng.normal()))
                s.carbs.append(DailyValue(date: day, value: kcal * 0.5 / 4 + 20 * rng.normal()))
                s.sugar.append(DailyValue(date: day, value: 60 + 15 * rng.normal()))
                s.fiber.append(DailyValue(date: day, value: 28 + 6 * rng.normal()))
                let micro: [(Micronutrient, Double, Double)] = [(.vitaminA, 850, 200), (.vitaminC, 110, 30), (.vitaminE, 11, 3),
                    (.calcium, 1100, 200), (.iron, 16, 3), (.potassium, 3800, 500), (.magnesium, 420, 60),
                    (.saturatedFat, 28, 6), (.sodium, 2900, 400)]
                for (m, mean, sd) in micro {
                    s.micronutrients[m, default: []].append(DailyValue(date: day, value: max(0, mean + sd * rng.normal())))
                }
                // Four meals; dinner drifts late about one day in four
                if back < 60 {
                    let late = rng.uniform() < 0.25
                    for (hour, share) in [(8.0, 0.2), (12.5, 0.3), (16.0, 0.15), (late ? 21.75 : 19.0, 0.35)] {
                        let at = day.addingTimeInterval((hour + 0.4 * rng.normal()) * 3600)
                        s.foodLog.append(Reading(date: at, value: kcal * share))
                    }
                }
            }

            if lifts {
                s.workouts.append(WorkoutSummary(id: rng.uuid(), start: cal.date(bySettingHour: 7, minute: 30, second: 0, of: day)!,
                                                 duration: (60 + 15 * rng.uniform()) * 60, name: "Strength",
                                                 isStrength: true, energy: 280 + 40 * rng.normal()))
            }
            if runs {
                s.workouts.append(WorkoutSummary(id: rng.uuid(), start: cal.date(bySettingHour: 10, minute: 0, second: 0, of: day)!,
                                                 duration: (35 + 15 * rng.uniform()) * 60, name: "Run",
                                                 isStrength: false, energy: 380 + 50 * rng.normal()))
            }
        }
        s.workouts.reverse()   // newest first, like HealthKitService

        // Same grouping as real data, so nights get stages, awakenings and wake time the real way.
        let grouped = SleepGrouping.group(segments)
        s.sleep = grouped.nights
        s.naps = grouped.naps
        s.sleepingHR = s.sleep.compactMap { n in sleepingHR[n.date].map { DailyValue(date: n.date, value: $0) } }
        // Workout heart rate: lifting alternates sets and rests, runs hold a steady pace.
        var workoutHR: [Reading] = []
        var effort: [Reading] = []
        var recovery: [Reading] = []
        for w in s.workouts {
            var t = w.start
            while t < w.end {
                let m = t.timeIntervalSince(w.start) / 60
                let bpm = w.isStrength ? 105 + 35 * max(0, sin(m / 3 * .pi)) : 158 + 6 * sin(m / 10)
                workoutHR.append(Reading(date: t, value: bpm + 3 * rng.normal()))
                t.addTimeInterval(10)
            }
            effort.append(Reading(date: w.end, value: (w.isStrength ? 7.5 : 6) + rng.normal()).rounded())
            recovery.append(Reading(date: w.end.addingTimeInterval(60), value: 28 + 4 * rng.normal()))
        }
        s.workouts = TrainingEngine.enrich(s.workouts, heartRate: workoutHR, effort: effort, estimatedEffort: [],
                                           hrRecovery: recovery, snapshot: s, day: today)

        for n in s.sleep.suffix(14) {
            let base = s.sleepingHR.value(on: n.date) ?? 52
            var t = n.start
            while t < n.end {
                s.nightHeartRate.append(Reading(date: t, value: base + 4 * sin(t.timeIntervalSince(n.start) / 5400 * .pi) + rng.normal()))
                if Int(t.timeIntervalSince(n.start)) % 900 == 0 {
                    s.nightRespiratory.append(Reading(date: t, value: 14.5 + 0.6 * rng.normal()))
                }
                t.addTimeInterval(300)
            }
            for k in 1...3 {
                let at = n.start.addingTimeInterval(n.end.timeIntervalSince(n.start) * Double(k) / 4)
                s.nightHRV.append(Reading(date: at, value: (s.hrv.value(on: n.date) ?? 58) * (1 + 0.15 * rng.normal())))
            }
        }
        return s
    }

    /// Sleep samples for one night: 90-minute cycles of core, deep and REM, with deep sleep front-loaded,
    /// REM back-loaded, brief stirs between cycles and a real awakening now and then.
    /// A Strong-style log for each mock strength workout: two alternating full-body days, about 2% stronger a month.
    public static func lifts(matching workouts: [WorkoutSummary], seed: UInt64 = 7) -> [LiftSession] {
        var rng = SplitMix64(seed: seed)
        let days: [[(name: String, top: Double, reps: Int)]] = [
            [("Squat (Barbell)", 80, 5), ("Bench Press (Barbell)", 62.5, 6), ("Bent Over Row (Barbell)", 55, 8)],
            [("Deadlift (Barbell)", 100, 5), ("Overhead Press (Barbell)", 40, 6), ("Pull Up", 0, 8)],
        ]
        let strength = workouts.filter(\.isStrength).sorted { $0.start < $1.start }
        let newest = strength.last?.start ?? .now
        return strength.enumerated().map { i, w in
            let monthsAgo = newest.timeIntervalSince(w.start) / (30 * 86400)
            let sets = days[i % 2].flatMap { ex -> [LiftSet] in
                let kg = ex.top == 0 ? 0 : (ex.top * (1 - 0.02 * monthsAgo) / 2.5).rounded() * 2.5
                let warmup = kg > 0 ? [LiftSet(exercise: ex.name, weight: (kg * 0.5 / 2.5).rounded() * 2.5, reps: 8, isWarmup: true)] : []
                return warmup + (0..<3).map { k in
                    LiftSet(exercise: ex.name, weight: kg, reps: k == 0 ? ex.reps : max(1, ex.reps - k + Int((rng.uniform() * 2).rounded(.down))),
                            rpe: 7.5 + Double(k) * 0.5)
                }
            }
            return LiftSession(start: w.start.addingTimeInterval(120), duration: w.duration - 240,
                               name: i % 2 == 0 ? "Full body A" : "Full body B", sets: sets)
        }
        .reversed()
    }

    /// Bedroom monitor readings every 5 minutes for the last nights: sealed nights climb towards 2,400 ppm,
    /// one in three is ventilated and stays under 900. After wake-up CO2 decays at 0.25 air changes per hour.
    public static func room(sleep: [SleepNight], nights: Int = 14, seed: UInt64 = 11) -> [RoomReading] {
        var rng = SplitMix64(seed: seed)
        var out: [RoomReading] = []
        for (i, n) in sleep.suffix(nights).enumerated() {
            let ventilated = i % 3 == 0
            let peak = ventilated ? 850.0 : 2400
            var t = n.start.addingTimeInterval(-3600)
            while t < n.end.addingTimeInterval(3 * 3600) {
                let co2: Double
                if t < n.start {
                    co2 = 520
                } else if t <= n.end {
                    let h = t.timeIntervalSince(n.start) / 3600
                    co2 = 520 + (peak - 520) * (1 - exp(-h / 4))
                } else {
                    let h = t.timeIntervalSince(n.end) / 3600
                    let atWake = 520 + (peak - 520) * (1 - exp(-n.end.timeIntervalSince(n.start) / 3600 / 4))
                    co2 = 420 + (atWake - 420) * exp(-0.25 * h)
                }
                let hour = Calendar.current.component(.hour, from: t)
                out.append(RoomReading(date: t, co2: co2 + 8 * rng.normal(), temperature: 21 + 0.3 * rng.normal(),
                                       humidity: 34 - 4 * min(1, max(0, t.timeIntervalSince(n.start) / 28800)) + rng.normal(),
                                       lux: hour >= 7 && hour < 10 ? 250 + 40 * rng.normal() : 2))
                t.addTimeInterval(300)
            }
        }
        return out
    }

    static func night(from bedtime: Date, hours: Double, rough: Bool, rng: inout SplitMix64) -> [SleepSegment] {
        var out: [SleepSegment] = []
        var t = bedtime
        let end = bedtime.addingTimeInterval(hours * 3600)
        func add(_ stage: SleepStage, _ minutes: Double) {
            let next = min(end, t.addingTimeInterval(max(1, minutes) * 60))
            if next > t { out.append(SleepSegment(start: t, end: next, stage: stage, fromWatch: true)) }
            t = next
        }
        var cycle = 0
        while t < end {
            let early = max(0, 1 - Double(cycle) / 4)
            add(.core, 25 + 10 * rng.uniform())
            add(.deep, 5 + 30 * early * (0.7 + 0.6 * rng.uniform()))
            add(.core, 15 + 10 * rng.uniform())
            add(.rem, 10 + 20 * (1 - early) + 5 * rng.uniform())
            if rng.uniform() < 0.7 { add(.awake, 0.5 + 1.5 * rng.uniform()) }          // brief stir
            if rng.uniform() < (rough ? 0.5 : 0.2) { add(.awake, 4 + 12 * rng.uniform()) } // real awakening
            cycle += 1
        }
        return out
    }
}

#endif

#if DEBUG
private extension Reading {
    func rounded() -> Reading { Reading(date: date, value: min(10, max(1, value.rounded()))) }
}
#endif
