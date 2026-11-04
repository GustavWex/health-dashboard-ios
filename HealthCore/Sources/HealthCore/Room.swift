import Foundation

/// One sample from the bedroom monitor (SCD41 for CO2, temperature and humidity; BH1750 or VEML7700 for light).
/// Any field can be missing; the sensors are read on their own schedules.
public struct RoomReading: Codable, Sendable, Equatable {
    public let date: Date
    public let co2: Double?           // ppm
    public let temperature: Double?   // °C, after the self-heating offset
    public let humidity: Double?      // % RH
    public let lux: Double?

    public init(date: Date, co2: Double? = nil, temperature: Double? = nil, humidity: Double? = nil, lux: Double? = nil) {
        self.date = date
        self.co2 = co2
        self.temperature = temperature
        self.humidity = humidity
        self.lux = lux
    }
}

/// The bedroom over one night's sleep window, dated by the morning like `SleepNight`.
public struct RoomNight: Identifiable, Sendable {
    public let date: Date
    public let readings: [RoomReading]
    public let co2Mean: Double?
    public let co2Peak: Double?
    public let co2AtWake: Double?
    public let minutesAbove1000: Double
    public let minutesAbove2000: Double
    public let temperatureMean: Double?
    public let humidityMean: Double?
    public let humidityMin: Double?
    public var id: Date { date }
}

/// Air change rate from the CO2 decay after the room empties: C(t) = C_out + (C0 − C_out)·e^(−λt).
public struct AirChange: Sendable {
    public let ach: Double            // λ, air changes per hour
    public let c0: Double             // ppm at the start of the decay
    public let outdoor: Double        // fitted C_out, ppm: should land near 420, so it doubles as a calibration check
    public let points: Int
    public let start: Date
}

public enum RoomCSVError: Error, Equatable {
    case noTimeColumn
    case noReadings
}

/// Reads exported room data. Two shapes are accepted:
/// - wide: one row per sample with columns like time, co2, temperature, humidity, lux;
/// - long, as InfluxDB exports it: annotation lines starting with #, then `_time`, `_field`, `_value` rows,
///   pivoted here into one reading per timestamp.
/// Times can be ISO 8601 or Unix seconds or milliseconds.
public enum RoomCSV {
    static let timeNames = ["_time", "time", "timestamp", "date", "datetime"]
    static let names: [String: [String]] = [
        "co2": ["co2", "co2_ppm", "co2ppm"],
        "temperature": ["temperature", "temp", "temperature_c", "temp_c"],
        "humidity": ["humidity", "rh", "humidity_pct", "relative_humidity"],
        "lux": ["lux", "light", "illuminance", "light_lux"],
    ]

    public static func parse(_ text: String) throws -> [RoomReading] {
        let delimiter: Character = text.prefix(2000).filter { $0 == ";" }.count > text.prefix(2000).filter { $0 == "," }.count ? ";" : ","
        let rows = StrongCSV.records(text, delimiter: delimiter).filter { !($0.first ?? "").hasPrefix("#") && $0 != [""] }
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { throw RoomCSVError.noReadings }
        guard let t = header.firstIndex(where: { timeNames.contains($0) }) else { throw RoomCSVError.noTimeColumn }
        let body = rows.dropFirst().filter { $0.count > t && $0 != header }
        var out: [RoomReading] = []
        if let field = header.firstIndex(of: "_field"), let value = header.firstIndex(of: "_value") {
            var byTime: [Date: [String: Double]] = [:]
            for r in body where r.count > max(field, value) {
                guard let d = date(r[t]), let v = StrongCSV.number(r[value].trimmingCharacters(in: .whitespaces)),
                      let key = canonical(r[field].lowercased()) else { continue }
                byTime[d, default: [:]][key] = v
            }
            out = byTime.map { RoomReading(date: $0.key, co2: $0.value["co2"], temperature: $0.value["temperature"],
                                           humidity: $0.value["humidity"], lux: $0.value["lux"]) }
        } else {
            let col = names.mapValues { aliases in header.firstIndex { aliases.contains($0) } }
            func v(_ r: [String], _ k: String) -> Double? {
                guard let i = col[k] ?? nil, i < r.count else { return nil }
                return StrongCSV.number(r[i].trimmingCharacters(in: .whitespaces))
            }
            out = body.compactMap { r in
                date(r[t]).map { RoomReading(date: $0, co2: v(r, "co2"), temperature: v(r, "temperature"),
                                            humidity: v(r, "humidity"), lux: v(r, "lux")) }
            }
        }
        out = out.filter { $0.co2 != nil || $0.temperature != nil || $0.humidity != nil || $0.lux != nil }
        guard !out.isEmpty else { throw RoomCSVError.noReadings }
        return out.sorted { $0.date < $1.date }
    }

    static func canonical(_ field: String) -> String? {
        names.first { $0.value.contains(field) }?.key
    }

    static func date(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let n = Double(s) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Several exports overlap; keep one reading per timestamp.
    public static func merge(_ batches: [[RoomReading]]) -> [RoomReading] {
        Dictionary(batches.flatMap { $0 }.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b }).values.sorted { $0.date < $1.date }
    }
}

public enum RoomEngine {
    /// Ventilation markers, design choices: 1,000 ppm is the long-standing rule of thumb for well-ventilated
    /// rooms; 2,000 ppm is where a DTU study in Campus Village bedrooms put unventilated nights (about 2,400 ppm
    /// against 835 ventilated) with worse sleep and next-day performance: Strøm-Tejsen, Zukowska, Wargocki and
    /// Wyon (2016), "The effects of bedroom air quality on sleep and next-day performance", Indoor Air 26(5).
    public static let wellVentilated = 1000.0
    public static let sealed = 2000.0
    /// Under 30% in winter is the spec's threshold for considering a humidifier.
    public static let dry = 30.0

    /// Readings inside each night's sleep window, summarised. Time above a level counts each sample until the
    /// next, capped at 10 minutes so a gap in the data doesn't count as time.
    public static func nights(_ readings: [RoomReading], sleep: [SleepNight]) -> [RoomNight] {
        guard !readings.isEmpty else { return [] }
        let sorted = readings.sorted { $0.date < $1.date }
        return sleep.compactMap { n in
            let lo = lowerBound(sorted, n.start)
            var hi = lo
            while hi < sorted.count && sorted[hi].date <= n.end { hi += 1 }
            let r = Array(sorted[lo..<hi])
            let co2 = r.compactMap(\.co2)
            guard !r.isEmpty else { return nil }
            var above1000 = 0.0, above2000 = 0.0
            for (i, x) in r.enumerated() {
                guard let c = x.co2 else { continue }
                let next = i + 1 < r.count ? r[i + 1].date : n.end
                let minutes = min(10, next.timeIntervalSince(x.date) / 60)
                if c > wellVentilated { above1000 += minutes }
                if c > sealed { above2000 += minutes }
            }
            let hum = r.compactMap(\.humidity)
            return RoomNight(date: n.date, readings: r, co2Mean: Stats.mean(co2), co2Peak: co2.max(),
                             co2AtWake: r.last(where: { $0.co2 != nil })?.co2, minutesAbove1000: above1000,
                             minutesAbove2000: above2000, temperatureMean: Stats.mean(r.compactMap(\.temperature)),
                             humidityMean: Stats.mean(hum), humidityMin: hum.min())
        }
    }

    /// Mean light per day between two hours, for "morning lux at the desk" and "evening lux in the room".
    public static func light(_ readings: [RoomReading], fromHour: Int, toHour: Int) -> [DailyValue] {
        let cal = Calendar.current
        let inWindow = readings.filter { r in
            guard r.lux != nil else { return false }
            let h = cal.component(.hour, from: r.date)
            return h >= fromHour && h < toHour
        }
        return Dictionary(grouping: inWindow) { cal.startOfDay(for: $0.date) }
            .compactMap { d, r in Stats.mean(r.compactMap(\.lux)).map { DailyValue(date: d, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// Fits the decay after you leave in the morning: from `start`, while CO2 keeps falling, for up to 3 hours.
    /// For each candidate C_out from 300 to 600 ppm, ln(C − C_out) is fitted linearly against time (slope −λ),
    /// and the C_out with the smallest squared error in ppm wins. Tracer gas decay, as in ASTM E741, with the
    /// CO2 you breathed out as the tracer. Needs 20 samples and a fall of at least 200 ppm.
    public static func airChange(_ readings: [RoomReading], after start: Date) -> AirChange? {
        let window = readings.filter { $0.date >= start && $0.date <= start.addingTimeInterval(3 * 3600) && $0.co2 != nil }
            .sorted { $0.date < $1.date }
        // Stop when someone comes back: a rise of more than 50 ppm over the running minimum
        var points: [(t: Double, c: Double)] = [], low = Double.infinity
        for r in window {
            let c = r.co2!
            if c > low + 50 { break }
            low = min(low, c)
            points.append((r.date.timeIntervalSince(start) / 3600, c))
        }
        guard points.count >= 20, let first = points.first?.c, let last = points.last?.c, first - last >= 200 else { return nil }
        var best: (sse: Double, fit: AirChange)?
        for outdoor in stride(from: 300.0, through: 600.0, by: 1.0) where outdoor < last - 5 {
            let xs = points.map(\.t), ys = points.map { log($0.c - outdoor) }
            guard let mx = Stats.mean(xs), let my = Stats.mean(ys) else { continue }
            let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            guard sxx > 0 else { continue }
            let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
            let c0 = exp(my - slope * mx)
            let sse = points.reduce(0) { acc, p in
                let e = p.c - (outdoor + c0 * exp(slope * p.t))
                return acc + e * e
            }
            if slope < 0, best.map({ sse < $0.sse }) ?? true {
                best = (sse, AirChange(ach: -slope, c0: outdoor + c0, outdoor: outdoor, points: points.count, start: start))
            }
        }
        return best?.fit
    }

    /// The decay after each morning's wake-up, newest first.
    public static func airChanges(_ readings: [RoomReading], sleep: [SleepNight]) -> [AirChange] {
        sleep.reversed().compactMap { airChange(readings, after: $0.end.addingTimeInterval(10 * 60)) }
    }

    static func lowerBound(_ r: [RoomReading], _ d: Date) -> Int {
        var lo = 0, hi = r.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if r[mid].date < d { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
