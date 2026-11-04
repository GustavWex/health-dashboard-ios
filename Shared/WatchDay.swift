import SwiftUI

/// The day as the watch and its complications show it, read from the App Group.
struct WatchDay {
    var score: Double?
    var zone: Int?
    var status: Int?
    var sleep: Double?
    var strain: Double?
    var strainLow: Double?
    var strainHigh: Double?
    var computed: Date?

    static let sleepColor = Color(red: 0.58, green: 0.44, blue: 0.95)
    static let strainColor = Color(red: 0.16, green: 0.47, blue: 0.95)
    static let good = Color(red: 0.20, green: 0.70, blue: 0.47)
    static let caution = Color(red: 0.93, green: 0.67, blue: 0.18)
    static let bad = Color(red: 0.86, green: 0.27, blue: 0.30)

    static let placeholder = WatchDay(score: 68, zone: 2, status: 2, sleep: 84, strain: 7.4, strainLow: 9, strainHigh: 13, computed: .now)

    static func load() -> WatchDay {
        let d = UserDefaults(suiteName: SharedKeys.group)
        func v(_ k: String) -> Double? { d?.object(forKey: k) as? Double }
        return WatchDay(score: v(SharedKeys.score), zone: d?.object(forKey: SharedKeys.zone) as? Int,
                        status: d?.object(forKey: SharedKeys.status) as? Int, sleep: v(SharedKeys.sleep),
                        strain: v(SharedKeys.strain), strainLow: v(SharedKeys.strainLow), strainHigh: v(SharedKeys.strainHigh),
                        computed: d?.object(forKey: SharedKeys.date) as? Date)
    }

    /// Yesterday's numbers aren't today's: blank them once the day has turned.
    var isToday: Bool { computed.map { Calendar.current.isDateInToday($0) } ?? false }

    var statusWord: String {
        guard isToday, let status else { return "--" }
        return ["Easy", "Steady", "Good"][min(max(status, 0), 2)]
    }

    var statusColor: Color {
        guard isToday, let status else { return .gray }
        return [Self.bad, Self.caution, Self.good][min(max(status, 0), 2)]
    }

    var zoneColor: Color {
        guard isToday, let zone else { return .gray }
        return [Self.bad, Self.caution, Self.good][min(max(zone, 0), 2)]
    }

    func text(_ v: Double?, _ digits: Int) -> String {
        guard isToday, let v else { return "--" }
        return String(format: "%.\(digits)f", v)
    }
}
