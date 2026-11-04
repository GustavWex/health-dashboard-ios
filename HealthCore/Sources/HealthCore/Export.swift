import Foundation

public enum ExportValue: Sendable, Equatable {
    case number(Double)
    case text(String)
    case missing
}

/// One row per day, ready for CSV or JSON. Morning and sleep columns describe the night that ended that morning;
/// activity, food and body columns describe the day itself.
public struct ExportTable: Sendable {
    public let columns: [String]
    public let rows: [[ExportValue]]

    /// RFC 4180: fields with commas, quotes or line breaks are quoted, quotes doubled. Numbers use a decimal point.
    public var csv: String {
        func field(_ v: ExportValue) -> String {
            switch v {
            case .missing: return ""
            case .number(let d): return d == d.rounded() && abs(d) < 1e12 ? String(Int(d)) : String(format: "%.3f", d)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            case .text(let s):
                return s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                    ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
            }
        }
        return ([columns.joined(separator: ",")] + rows.map { $0.map(field).joined(separator: ",") })
            .joined(separator: "\n") + "\n"
    }

    /// An array of objects, numbers as numbers and missing values as null.
    public var json: Data {
        let objects = rows.map { row in
            Dictionary(uniqueKeysWithValues: zip(columns, row).map { k, v -> (String, Any) in
                switch v {
                case .number(let d): return (k, d)
                case .text(let s): return (k, s)
                case .missing: return (k, NSNull())
                }
            })
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    public func suffix(days: Int) -> ExportTable {
        ExportTable(columns: columns, rows: Array(rows.suffix(days)))
    }
}

public enum DailyExport {
    public static func table(_ s: HealthSnapshot, recovery: [DailyValue], training: [TrainingDay], lifts: [LiftSession],
                             tags: [(day: Date, tags: [String])], needHours: Double, days: Int, endingOn day: Date,
                             feel: [DailyValue] = []) -> ExportTable {
        let cal = Calendar.current
        func index(_ v: [DailyValue]) -> [Date: Double] {
            Dictionary(v.map { (cal.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        let rec = index(recovery), hrv = index(s.hrv), rhr = index(s.restingHR), rr = index(s.respiratoryRate),
            temp = index(s.wristTemp), spo2 = index(s.oxygenSaturation), steps = index(s.steps), active = index(s.activeEnergy),
            food = index(s.dietaryEnergy.filter { $0.value > NutritionEngine.loggedMinimum }), protein = index(s.protein),
            fat = index(s.fat), carbs = index(s.carbs), fiber = index(s.fiber), sugar = index(s.sugar), weight = index(s.weight),
            trend = index(BodyEngine.ema(s.weight)), bodyFat = index(s.bodyFat), lean = index(s.leanMass),
            muscle = index(s.muscleMass), water = index(s.bodyWater), bone = index(s.boneMass), visceral = index(s.visceralFat),
            bmr = index(s.bmr), metabolicAge = index(s.metabolicAge), felt = index(feel),
            morningLux = index(RoomEngine.light(s.room, fromHour: 6, toHour: 10))
        let roomNights = Dictionary(RoomEngine.nights(s.room, sleep: s.sleep).map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let nights = Dictionary(s.sleep.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let mealGap = Dictionary(NutritionEngine.lastMeals(NutritionEngine.meals(s.foodLog), nights: s.sleep)
            .map { (cal.startOfDay(for: $0.night), $0.gapHours) }, uniquingKeysWith: { a, _ in a })
        let train = Dictionary(training.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let workouts = Dictionary(grouping: s.workouts) { cal.startOfDay(for: $0.start) }
        let volume = Dictionary(grouping: lifts) { cal.startOfDay(for: $0.start) }
        let tagged = Dictionary(tags.map { (cal.startOfDay(for: $0.day), $0.tags) }, uniquingKeysWith: { $0 + $1 })

        func n(_ v: Double?) -> ExportValue { v.map { .number(($0 * 100).rounded() / 100) } ?? .missing }
        func clock(_ d: Date?) -> ExportValue {
            guard let d else { return .missing }
            let c = cal.dateComponents([.hour, .minute], from: d)
            return .text(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
        }

        let columns = ["date", "feel", "recovery", "hrv_ms", "resting_hr_bpm", "respiratory_rate", "wrist_temp_c", "spo2_pct",
                       "sleep_h", "bedtime", "wake", "sleep_efficiency_pct", "awakenings", "waso_min", "deep_h", "rem_h",
                       "sleep_score", "last_meal_to_sleep_h",
                       "strain", "trimp", "effort_load", "workout_min", "workouts", "lifting_volume_kg", "steps", "active_kcal",
                       "intake_kcal", "protein_g", "fat_g", "carbs_g", "fiber_g", "sugar_g",
                       "weight_kg", "trend_weight_kg", "body_fat_pct", "lean_mass_kg", "muscle_mass_kg", "body_water_kg",
                       "bone_mass_kg", "visceral_fat", "bmr_kcal", "metabolic_age",
                       "room_co2_night_ppm", "room_co2_wake_ppm", "room_temp_night_c", "room_humidity_night_pct", "morning_lux", "tags"]
        let dateFormat = DateFormatter()
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        dateFormat.dateFormat = "yyyy-MM-dd"
        let rows = (0..<days).reversed().map { back -> [ExportValue] in
            let d = cal.date(byAdding: .day, value: -back, to: day)!
            let night = nights[d]
            let w = workouts[d] ?? []
            let t = train[d]
            return [
                .text(dateFormat.string(from: d)), n(felt[d]), n(rec[d]), n(hrv[d]), n(rhr[d]), n(rr[d]), n(temp[d]), n(spo2[d].map { $0 * 100 }),
                n(night.map { $0.asleep / 3600 }), clock(night?.start), clock(night?.end),
                n(night.flatMap { n in n.end > n.start ? 100 * n.asleep / n.end.timeIntervalSince(n.start) : nil }),
                n(night.map { Double($0.awakenings) }), n(night.map { $0.waso / 60 }),
                n(night.map { $0.deep / 3600 }), n(night.map { $0.rem / 3600 }),
                n(night.flatMap { SleepScoreEngine.score(s, night: $0, needHours: needHours).score }), n(mealGap[d]),
                n(t?.strain), n(t.map(\.trimp)), n(t.map(\.srpe)),
                n(w.isEmpty ? 0 : w.reduce(0) { $0 + $1.duration / 60 }),
                w.isEmpty ? .missing : .text(w.map(\.name).joined(separator: "; ")),
                n(volume[d].map { $0.reduce(0) { $0 + LiftingEngine.volumeLoad($1.sets) } }),
                n(steps[d]), n(active[d]), n(food[d]),
                n(food[d] == nil ? nil : protein[d]), n(food[d] == nil ? nil : fat[d]), n(food[d] == nil ? nil : carbs[d]),
                n(food[d] == nil ? nil : fiber[d]), n(food[d] == nil ? nil : sugar[d]),
                n(weight[d]), n(trend[d]), n(bodyFat[d].map { $0 * 100 }), n(lean[d]),
                n(muscle[d]), n(water[d]), n(bone[d]), n(visceral[d]), n(bmr[d]), n(metabolicAge[d]),
                n(roomNights[d]?.co2Mean), n(roomNights[d]?.co2AtWake), n(roomNights[d]?.temperatureMean),
                n(roomNights[d]?.humidityMean), n(morningLux[d]),
                tagged[d].map { .text($0.joined(separator: "; ")) } ?? .missing,
            ]
        }
        return ExportTable(columns: columns, rows: rows)
    }
}
