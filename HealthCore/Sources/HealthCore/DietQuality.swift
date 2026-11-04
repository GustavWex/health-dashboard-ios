import Foundation

/// One nutrient's part in the food score.
public struct NutrientScore: Identifiable, Sendable {
    public let name: String
    public let amount: Double          // per day, as eaten
    public let unit: String
    public let reference: Double       // the target, or the limit, in the same unit
    public let percent: Double         // amount as a share of the reference
    public let isLimit: Bool           // true for a maximum (sodium, saturated fat, an upper intake level)
    public let penalty: Double         // points taken off the score; 0 for targets and for limits not exceeded
    public var id: String { name + (isLimit ? " limit" : "") }
}

public struct DietQuality: Sendable {
    public let score: Double           // 0 to 100
    public let nutrients: [NutrientScore]
    public let encourage: Double       // mean % of target over the nutrients with a target, each capped at 100
    public let penalty: Double         // total points lost to limits
}

/// The day's food against targets for every nutrient Apple Health stores, the way Cronometer or MyFitnessPal
/// compare a day with their goals, plus penalties for too much.
///
/// Those apps don't share their goals with Apple Health (it has no type for them), so the targets are:
/// - protein from your g/kg target in Settings, and fiber at 14 g per 1,000 kcal (Dietary Guidelines for
///   Americans 2020 to 2025);
/// - every vitamin and mineral at its US daily value from the FDA's 2016 Nutrition Facts rule (21 CFR 101.9),
///   which is also what Cronometer's default targets start from;
/// - water at 2 L from drinks: EFSA (2010) sets 2.5 L a day for men, about 80% of it from drinks.
///
/// Limits cost points when exceeded:
/// - sodium 2,300 mg, cholesterol 300 mg (FDA daily values) and caffeine 400 mg (FDA's safe-intake level);
/// - saturated fat 10% of energy (Dietary Guidelines), total fat 35% of energy (top of the Institute of Medicine's
///   acceptable range), total sugar 25% of energy (a lenient stand-in: Health stores total sugar, not added sugar,
///   and the WHO's 10% applies to free sugars only);
/// - the Institute of Medicine's tolerable upper intake levels where food can plausibly reach them (vitamins A, C,
///   D and B6, calcium, iron, zinc, selenium, copper, manganese, iodine, phosphorus, molybdenum). Upper levels that
///   apply only to supplements (niacin, folate, vitamin E, magnesium) are left out.
///
/// Score = mean % of target (each capped at 100) minus, for every limit, half a point per percent over it (at most
/// 40 per limit), clamped to 0 to 100. Needs the day's calories and at least 4 nutrients with a target.
public enum DietQualityEngine {
    public static let targets: [(name: String, unit: String, value: Double)] = [
        ("Vitamin A", "µg", 900), ("Vitamin C", "mg", 90), ("Vitamin D", "µg", 20), ("Vitamin E", "mg", 15),
        ("Vitamin K", "µg", 120), ("Thiamin", "mg", 1.2), ("Riboflavin", "mg", 1.3), ("Niacin", "mg", 16),
        ("Vitamin B6", "mg", 1.7), ("Folate", "µg", 400), ("Vitamin B12", "µg", 2.4), ("Biotin", "µg", 30),
        ("Pantothenic acid", "mg", 5), ("Calcium", "mg", 1300), ("Iron", "mg", 18), ("Phosphorus", "mg", 1250),
        ("Iodine", "µg", 150), ("Magnesium", "mg", 420), ("Zinc", "mg", 11), ("Selenium", "µg", 55),
        ("Copper", "mg", 0.9), ("Manganese", "mg", 2.3), ("Chromium", "µg", 35), ("Molybdenum", "µg", 45),
        ("Potassium", "mg", 4700), ("Water", "mL", 2000),
    ]
    public static let absoluteLimits: [(name: String, unit: String, value: Double)] = [
        ("Sodium", "mg", 2300), ("Cholesterol", "mg", 300), ("Caffeine", "mg", 400),
    ]
    /// Limits as a share of the day's energy: (name, kcal per gram, maximum share).
    public static let energyLimits: [(name: String, kcalPerGram: Double, share: Double)] = [
        ("Saturated fat", 9, 0.10), ("Fat", 9, 0.35), ("Sugar", 4, 0.25),
    ]
    public static let upperLevels: [(name: String, value: Double)] = [
        ("Vitamin A", 3000), ("Vitamin C", 2000), ("Vitamin D", 100), ("Vitamin B6", 100), ("Calcium", 2500),
        ("Iron", 45), ("Zinc", 40), ("Selenium", 400), ("Copper", 10), ("Manganese", 11), ("Iodine", 1100),
        ("Phosphorus", 4000), ("Molybdenum", 2000),
    ]

    static func penalty(percentOver: Double) -> Double { min(40, max(0, percentOver) * 0.5) }

    /// - Parameters:
    ///   - amounts: grams, milligrams, micrograms or millilitres per day, keyed by the names above (plus Protein,
    ///     Fiber, Fat and Sugar in grams).
    ///   - proteinTarget: grams for the day; nil skips protein.
    public static func score(kcal: Double, amounts: [String: Double], proteinTarget: Double?) -> DietQuality? {
        guard kcal > 300 else { return nil }
        var out: [NutrientScore] = []
        func target(_ name: String, _ unit: String, _ ref: Double) {
            guard let a = amounts[name], ref > 0 else { return }
            out.append(NutrientScore(name: name, amount: a, unit: unit, reference: ref, percent: 100 * a / ref, isLimit: false, penalty: 0))
        }
        func limit(_ name: String, _ unit: String, _ ref: Double) {
            guard let a = amounts[name], ref > 0 else { return }
            let pct = 100 * a / ref
            out.append(NutrientScore(name: name, amount: a, unit: unit, reference: ref, percent: pct, isLimit: true,
                                     penalty: penalty(percentOver: pct - 100)))
        }
        if let p = proteinTarget { target("Protein", "g", p) }
        target("Fiber", "g", 14 * kcal / 1000)
        for t in targets { target(t.name, t.unit, t.value) }
        let encouraged = out.filter { !$0.isLimit }
        guard encouraged.count >= 4 else { return nil }
        for l in absoluteLimits { limit(l.name, l.unit, l.value) }
        for l in energyLimits { limit(l.name, "g", kcal * l.share / l.kcalPerGram) }
        for u in upperLevels {
            let unit = targets.first { $0.name == u.name }?.unit ?? "mg"
            limit(u.name, unit, u.value)
        }
        let encourage = Stats.mean(encouraged.map { min(100, $0.percent) }) ?? 0
        let lost = out.reduce(0) { $0 + $1.penalty }
        return DietQuality(score: max(0, min(100, encourage - lost)), nutrients: out, encourage: encourage, penalty: lost)
    }

    /// The day's amounts from a snapshot, keyed by the names used above.
    public static func amounts(_ s: HealthSnapshot, on day: Date) -> [String: Double] {
        var a: [String: Double] = [:]
        a["Protein"] = s.protein.value(on: day)
        a["Fiber"] = s.fiber.value(on: day)
        a["Fat"] = s.fat.value(on: day)
        a["Sugar"] = s.sugar.value(on: day)
        for m in Micronutrient.allCases { a[name(m)] = s.micronutrients[m]?.value(on: day) }
        return a.compactMapValues { $0 }
    }

    public static func score(_ s: HealthSnapshot, on day: Date, proteinTarget: Double?) -> DietQuality? {
        guard let kcal = s.dietaryEnergy.value(on: day) else { return nil }
        return score(kcal: kcal, amounts: amounts(s, on: day), proteinTarget: proteinTarget)
    }

    /// How many of the nutrients Apple Health can store arrived for the day.
    public static func coverage(_ s: HealthSnapshot, on day: Date) -> (seen: Int, total: Int) {
        (amounts(s, on: day).count, Micronutrient.allCases.count + 4)
    }

    public static func name(_ m: Micronutrient) -> String {
        switch m {
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminK: "Vitamin K"
        case .thiamin: "Thiamin"
        case .riboflavin: "Riboflavin"
        case .niacin: "Niacin"
        case .vitaminB6: "Vitamin B6"
        case .folate: "Folate"
        case .vitaminB12: "Vitamin B12"
        case .biotin: "Biotin"
        case .pantothenicAcid: "Pantothenic acid"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .phosphorus: "Phosphorus"
        case .iodine: "Iodine"
        case .magnesium: "Magnesium"
        case .zinc: "Zinc"
        case .selenium: "Selenium"
        case .copper: "Copper"
        case .manganese: "Manganese"
        case .chromium: "Chromium"
        case .molybdenum: "Molybdenum"
        case .chloride: "Chloride"
        case .potassium: "Potassium"
        case .sodium: "Sodium"
        case .saturatedFat: "Saturated fat"
        case .monounsaturatedFat: "Monounsaturated fat"
        case .polyunsaturatedFat: "Polyunsaturated fat"
        case .cholesterol: "Cholesterol"
        case .caffeine: "Caffeine"
        case .water: "Water"
        }
    }
}
