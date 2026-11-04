import Foundation
import HealthKit
import HealthCore

/// Read-only access to Apple Health. HKHealthStore is thread safe, hence @unchecked Sendable.
final class HealthKitService: @unchecked Sendable {
    private let store = HKHealthStore()
    private let calendar = Calendar.current

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let quantityIDs: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate, .appleSleepingWristTemperature,
        .oxygenSaturation, .activeEnergyBurned, .basalEnergyBurned, .stepCount,
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .height,
        .dietaryEnergyConsumed, .dietaryProtein, .dietaryFatTotal, .dietaryCarbohydrates,
        .dietarySugar, .dietaryFiber
    ] + HealthKitService.micronutrientTypes.map(\.1)

    /// Every other nutrition type in Apple Health, with the unit the food score uses.
    static let micronutrientTypes: [(Micronutrient, HKQuantityTypeIdentifier, HKUnit)] = {
        let mg = HKUnit.gramUnit(with: .milli), ug = HKUnit.gramUnit(with: .micro)
        return [
            (.vitaminA, .dietaryVitaminA, ug), (.vitaminC, .dietaryVitaminC, mg), (.vitaminD, .dietaryVitaminD, ug),
            (.vitaminE, .dietaryVitaminE, mg), (.vitaminK, .dietaryVitaminK, ug), (.thiamin, .dietaryThiamin, mg),
            (.riboflavin, .dietaryRiboflavin, mg), (.niacin, .dietaryNiacin, mg), (.vitaminB6, .dietaryVitaminB6, mg),
            (.folate, .dietaryFolate, ug), (.vitaminB12, .dietaryVitaminB12, ug), (.biotin, .dietaryBiotin, ug),
            (.pantothenicAcid, .dietaryPantothenicAcid, mg), (.calcium, .dietaryCalcium, mg), (.iron, .dietaryIron, mg),
            (.phosphorus, .dietaryPhosphorus, mg), (.iodine, .dietaryIodine, ug), (.magnesium, .dietaryMagnesium, mg),
            (.zinc, .dietaryZinc, mg), (.selenium, .dietarySelenium, ug), (.copper, .dietaryCopper, mg),
            (.manganese, .dietaryManganese, mg), (.chromium, .dietaryChromium, ug), (.molybdenum, .dietaryMolybdenum, ug),
            (.chloride, .dietaryChloride, mg), (.potassium, .dietaryPotassium, mg), (.sodium, .dietarySodium, mg),
            (.saturatedFat, .dietaryFatSaturated, .gram()), (.monounsaturatedFat, .dietaryFatMonounsaturated, .gram()),
            (.polyunsaturatedFat, .dietaryFatPolyunsaturated, .gram()), (.cholesterol, .dietaryCholesterol, mg),
            (.caffeine, .dietaryCaffeine, mg), (.water, .dietaryWater, .literUnit(with: .milli)),
        ]
    }()

    static let strengthTypes: Set<HKWorkoutActivityType> = [
        .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining
    ]

    func requestAuthorization() async throws {
        var read: Set<HKObjectType> = Set(quantityIDs.map { HKQuantityType($0) })
        read.insert(HKCategoryType(.sleepAnalysis))
        read.insert(HKObjectType.workoutType())
        read.insert(HKCharacteristicType(.dateOfBirth))
        read.insert(HKCharacteristicType(.biologicalSex))
        read.insert(HKQuantityType(.heartRate))
        read.insert(HKQuantityType(.heartRateRecoveryOneMinute))
        if #available(iOS 18.0, *) {
            read.insert(HKQuantityType(.appleSleepingBreathingDisturbances))
            read.insert(HKQuantityType(.workoutEffortScore))
            read.insert(HKQuantityType(.estimatedWorkoutEffortScore))
        }
        try await store.requestAuthorization(toShare: [], read: read)
    }

    func fetchSnapshot(days: Int) async -> HealthSnapshot {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let kcal = HKUnit.kilocalorie()
        let kg = HKUnit.gramUnit(with: .kilo)
        let ms = HKUnit.secondUnit(with: .milli)

        // Each query fails independently, so missing permissions only blank that metric.
        async let segments = try? sleepSegments(days: days)
        async let hrvRaw = try? readings(.heartRateVariabilitySDNN, ms, days: days)
        async let respRaw = try? readings(.respiratoryRate, bpm, days: days)
        async let spo2Raw = try? readings(.oxygenSaturation, .percent(), days: days)
        async let weightRaw = try? readings(.bodyMass, kg, days: days)
        async let fatRaw = try? readings(.bodyFatPercentage, .percent(), days: days)
        async let leanRaw = try? readings(.leanBodyMass, kg, days: days)
        async let rhr = try? daily(.restingHeartRate, bpm, sum: false, days: days)
        async let temp = try? daily(.appleSleepingWristTemperature, .degreeCelsius(), sum: false, days: days)
        async let active = try? daily(.activeEnergyBurned, kcal, sum: true, days: days)
        async let basal = try? daily(.basalEnergyBurned, kcal, sum: true, days: days)
        async let steps = try? daily(.stepCount, .count(), sum: true, days: days)
        async let food = try? daily(.dietaryEnergyConsumed, kcal, sum: true, days: days)
        async let protein = try? daily(.dietaryProtein, .gram(), sum: true, days: days)
        async let fat = try? daily(.dietaryFatTotal, .gram(), sum: true, days: days)
        async let carbs = try? daily(.dietaryCarbohydrates, .gram(), sum: true, days: days)
        async let sugar = try? daily(.dietarySugar, .gram(), sum: true, days: days)
        async let fiber = try? daily(.dietaryFiber, .gram(), sum: true, days: days)
        // Individual food samples keep the time eaten; 60 days is plenty for meal timing.
        async let foodLog = try? readings(.dietaryEnergyConsumed, kcal, days: min(days, 60))
        async let wk = try? workouts(days: days)

        // Overnight metrics need the nights first, so they are bucketed after the raw fetches land.
        let sleep = SleepGrouping.group(await segments ?? [])

        // Heart rate is only fetched inside recent sleep windows: the full stream, with workouts at one
        // sample per second, would be hundreds of thousands of samples. 75 nights cover the 60-day baseline.
        let baselineNights = Array(sleep.nights.suffix(75))
        let chartNights = Array(sleep.nights.suffix(14))
        let hrNight = (try? await readings(.heartRate, bpm, during: baselineNights)) ?? []
        let disturbances = await breathingDisturbances(days: days)
        let hrv = await hrvRaw ?? []
        let resp = await respRaw ?? []

        // Workout heart rate only inside workout windows, for the last 180 days at most: enough for the
        // 42-day fitness constant to settle, without pulling years of one-per-second samples.
        let allWorkouts = await wk ?? []
        let cutoff = startDate(daysBack: min(days, 180))
        let recentWorkouts = allWorkouts.filter { $0.start >= cutoff }
        let workoutHR = (try? await readings(.heartRate, bpm, windows: recentWorkouts.map { ($0.start, $0.end) })) ?? []
        let effort = await effortScores(days: days)
        let recovery = (try? await readings(.heartRateRecoveryOneMinute, bpm, days: days)) ?? []

        var snapshot = HealthSnapshot(
            hrv: Overnight.daily(hrv, nights: sleep.nights),
            restingHR: await rhr ?? [],
            respiratoryRate: Overnight.daily(resp, nights: sleep.nights),
            wristTemp: await temp ?? [],
            oxygenSaturation: Overnight.daily(await spo2Raw ?? [], nights: sleep.nights),
            sleep: sleep.nights,
            naps: sleep.naps,
            sleepingHR: Overnight.daily(hrNight, nights: baselineNights),
            breathingDisturbances: disturbances,
            nightHeartRate: Overnight.inside(hrNight, nights: chartNights),
            nightRespiratory: Overnight.inside(resp, nights: chartNights),
            nightHRV: Overnight.inside(hrv, nights: chartNights),
            activeEnergy: await active ?? [],
            basalEnergy: await basal ?? [],
            steps: await steps ?? [],
            weight: Daily.first(await weightRaw ?? []),
            bodyFat: Daily.first(await fatRaw ?? []),
            leanMass: Daily.first(await leanRaw ?? []),
            dietaryEnergy: await food ?? [],
            protein: await protein ?? [],
            workouts: allWorkouts,
            profile: profile()
        )
        snapshot.profile.height = (try? await readings(.height, .meter(), days: 3650))?.last?.value
        snapshot.micronutrients = await micronutrients(days: days)
        snapshot.fat = await fat ?? []
        snapshot.carbs = await carbs ?? []
        snapshot.sugar = await sugar ?? []
        snapshot.fiber = await fiber ?? []
        snapshot.foodLog = await foodLog ?? []
        snapshot.workouts = TrainingEngine.enrich(allWorkouts, heartRate: workoutHR, effort: effort.own,
                                                  estimatedEffort: effort.estimated, hrRecovery: recovery,
                                                  snapshot: snapshot, day: calendar.startOfDay(for: .now))
        return snapshot
    }

    // MARK: - Queries

    private func startDate(daysBack days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now))!
    }

    /// Characteristics throw when not shared; each is optional on its own.
    private func profile() -> Profile {
        let birth = (try? store.dateOfBirthComponents()).flatMap { calendar.date(from: $0) }
        let sex: Sex?
        switch (try? store.biologicalSex())?.biologicalSex {
        case .male?: sex = .male
        case .female?: sex = .female
        default: sex = nil
        }
        return Profile(birthDate: birth, sex: sex)
    }

    /// Daily sum (cumulative types) or daily average (discrete types).
    private func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, sum: Bool, days: Int) async throws -> [DailyValue] {
        let start = startDate(daysBack: days)
        let end = Date.now
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: sum ? .cumulativeSum : .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var out: [DailyValue] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let q = sum ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out.append(DailyValue(date: stats.startDate, value: q.doubleValue(for: unit))) }
        }
        return out
    }

    /// Daily totals for the diet quality nutrients. Each one fails on its own if not shared or not written.
    private func micronutrients(days: Int) async -> [Micronutrient: [DailyValue]] {
        await withTaskGroup(of: (Micronutrient, [DailyValue]?).self) { group in
            for (n, id, unit) in Self.micronutrientTypes {
                group.addTask { (n, try? await self.daily(id, unit, sum: true, days: min(days, 120))) }
            }
            var out: [Micronutrient: [DailyValue]] = [:]
            for await (n, v) in group { if let v, !v.isEmpty { out[n] = v } }
            return out
        }
    }

    /// Raw samples, oldest first. HealthCore does the per-day aggregation.
    private func readings(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, days: Int) async throws -> [Reading] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id),
                                         predicate: HKQuery.predicateForSamples(withStart: startDate(daysBack: days), end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    /// Raw samples restricted to the given nights' sleep windows, with the same margin as `Overnight`.
    private func readings(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, during nights: [SleepNight]) async throws -> [Reading] {
        try await readings(id, unit, windows: nights.map {
            ($0.start.addingTimeInterval(-Overnight.margin), $0.end.addingTimeInterval(Overnight.margin))
        })
    }

    /// Raw samples inside any of the given time windows, as one query with an OR predicate.
    private func readings(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, windows: [(Date, Date)]) async throws -> [Reading] {
        guard !windows.isEmpty else { return [] }
        let predicates = windows.map { HKQuery.predicateForSamples(withStart: $0.0, end: $0.1) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id),
                                         predicate: NSCompoundPredicate(orPredicateWithSubpredicates: predicates))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    /// Workout effort ratings (iOS 18): your own and the watch's estimates, matched to workouts by time.
    private func effortScores(days: Int) async -> (own: [Reading], estimated: [Reading]) {
        guard #available(iOS 18.0, *) else { return ([], []) }
        let unit = HKUnit.appleEffortScore()
        let own = (try? await readings(.workoutEffortScore, unit, days: days)) ?? []
        let estimated = (try? await readings(.estimatedWorkoutEffortScore, unit, days: days)) ?? []
        return (own, estimated)
    }

    /// Apple's nightly breathing disturbances (iOS 18, newer watch models). Empty when not recorded.
    private func breathingDisturbances(days: Int) async -> [DailyValue] {
        guard #available(iOS 18.0, *) else { return [] }
        return (try? await daily(.appleSleepingBreathingDisturbances, .count(), sum: false, days: days)) ?? []
    }

    /// Maps sleep analysis samples to plain segments; grouping into nights and naps lives in HealthCore.
    private func sleepSegments(days: Int) async throws -> [SleepSegment] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: startDate(daysBack: days), end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let segments = try await descriptor.result(for: store).compactMap { s -> SleepSegment? in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepUnspecified: stage = .unspecified
            case .awake: stage = .awake
            default: stage = .inBed
            }
            return SleepSegment(start: s.startDate, end: s.endDate, stage: stage,
                                fromWatch: s.sourceRevision.productType?.hasPrefix("Watch") == true)
        }
        return segments
    }

    private func workouts(days: Int) async throws -> [WorkoutSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: startDate(daysBack: days), end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let energyType = HKQuantityType(.activeEnergyBurned)
        return try await descriptor.result(for: store).map { w in
            WorkoutSummary(
                id: w.uuid,
                start: w.startDate,
                duration: w.duration,
                name: w.workoutActivityType.displayName,
                isStrength: Self.strengthTypes.contains(w.workoutActivityType),
                energy: w.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            )
        }
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining: "Strength"
        case .functionalStrengthTraining: "Functional strength"
        case .coreTraining: "Core"
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .swimming: "Swim"
        case .highIntensityIntervalTraining: "HIIT"
        case .soccer: "Football"
        case .yoga: "Yoga"
        case .hiking: "Hike"
        default: "Workout"
        }
    }
}
