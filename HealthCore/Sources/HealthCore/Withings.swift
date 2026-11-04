import Foundation

/// One Withings weigh-in: all measures taken together, already decoded to real units.
public struct WithingsGroup: Codable, Sendable, Equatable {
    public let id: Int
    public let date: Date
    public let measures: [Int: Double]   // measure type id to value

    public init(id: Int, date: Date, measures: [Int: Double]) {
        self.id = id
        self.date = date
        self.measures = measures
    }
}

public struct WithingsPage: Sendable {
    public let groups: [WithingsGroup]
    public let more: Bool
    public let offset: Int?
    public let updateTime: Int?
}

public enum WithingsError: Error, Equatable {
    case status(Int)       // non-zero API status, e.g. 401 for an invalid token
    case malformed
}

/// Body composition from the Withings API, for what Apple Health has no type for. Weight, fat and lean mass
/// still come from Apple Health, where the Withings app already writes them.
public enum WithingsBody {
    /// Measure type ids, from the Withings API reference (developer.withings.com/openapi.yaml, getmeas meastype).
    public enum Kind: Int, CaseIterable, Sendable {
        case muscleMass = 76      // kg
        case bodyWater = 77       // kg ("hydration")
        case boneMass = 88        // kg
        case visceralFat = 170    // index, no unit
        case bmr = 226            // basal metabolic rate, kcal/day
        case metabolicAge = 227   // years
    }

    /// Parses a `measure?action=getmeas` response. Each measure is `value × 10^unit`.
    public static func parse(_ data: Data) throws -> WithingsPage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int else { throw WithingsError.malformed }
        guard status == 0 else { throw WithingsError.status(status) }
        let body = json["body"] as? [String: Any] ?? [:]
        let groups = (body["measuregrps"] as? [[String: Any]] ?? []).compactMap { g -> WithingsGroup? in
            guard let id = g["grpid"] as? Int, let t = g["date"] as? Double ?? (g["date"] as? Int).map(Double.init) else { return nil }
            var m: [Int: Double] = [:]
            for x in g["measures"] as? [[String: Any]] ?? [] {
                guard let type = x["type"] as? Int, let v = x["value"] as? Double ?? (x["value"] as? Int).map(Double.init),
                      let unit = x["unit"] as? Int else { continue }
                m[type] = v * pow(10, Double(unit))
            }
            return WithingsGroup(id: id, date: Date(timeIntervalSince1970: t), measures: m)
        }
        let update = body["updatetime"] as? Int ?? (body["updatetime"] as? String).flatMap(Int.init)
        return WithingsPage(groups: groups, more: (body["more"] as? Int ?? 0) != 0, offset: body["offset"] as? Int, updateTime: update)
    }

    /// Newer versions of a group replace older ones (same id), oldest first.
    public static func merge(_ old: [WithingsGroup], _ new: [WithingsGroup]) -> [WithingsGroup] {
        var byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for g in new { byID[g.id] = g }
        return byID.values.sorted { $0.date < $1.date }
    }

    /// First weigh-in of each day per measure, the same rule as weight from Apple Health (morning hydration is
    /// the most consistent).
    public static func daily(_ groups: [WithingsGroup], _ kind: Kind) -> [DailyValue] {
        Daily.first(groups.compactMap { g in g.measures[kind.rawValue].map { Reading(date: g.date, value: $0) } })
    }

    public static func apply(_ groups: [WithingsGroup], to s: inout HealthSnapshot) {
        s.muscleMass = daily(groups, .muscleMass)
        s.bodyWater = daily(groups, .bodyWater)
        s.boneMass = daily(groups, .boneMass)
        s.visceralFat = daily(groups, .visceralFat)
        s.bmr = daily(groups, .bmr)
        s.metabolicAge = daily(groups, .metabolicAge)
    }
}
