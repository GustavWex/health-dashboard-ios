import Foundation

/// What a smart scale measures, in the units the snapshot uses.
public enum BodyMeasure: String, CaseIterable, Sendable {
    case weight          // kg
    case bodyFat         // fraction 0-1
    case leanMass        // kg, fat-free mass
    case muscleMass      // kg
    case bodyWater       // kg
    case boneMass        // kg
    case visceralFat     // index, no unit
    case bmr             // kcal/day
    case metabolicAge    // years
}

/// One weigh-in from a scale app export.
public struct BodyEntry: Sendable, Equatable {
    public let date: Date
    public let values: [BodyMeasure: Double]

    public init(date: Date, values: [BodyMeasure: Double]) {
        self.date = date
        self.values = values
    }
}

public enum BodyImportError: Error, Equatable {
    case noDateColumn
    case noMeasures
}

/// Reads the CSV export of most smart scale apps (Withings, Renpho, Eufy, Garmin, Fitbit, Xiaomi Zepp and others),
/// matching columns by name instead of by brand. Headers like "Weight (kg)", "Body Fat(%)", "Muscle Mass(kg)" or
/// "Hydration (kg)" are split into a name and a unit; cells may carry their own unit ("75.2 kg", "18.5 %").
/// Shares and masses are converted with the same row's weight where needed: fat mass to a fat share, water and
/// muscle percentages to kg. Pounds are converted at 0.45359237 kg (1959 agreement). Unknown columns are ignored.
public enum BodyCSV {
    public static func parse(_ text: String, timeZone: TimeZone = .current) throws -> [BodyEntry] {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows = StrongCSV.records(text, delimiter: delimiter)
        guard !rows.isEmpty else { throw BodyImportError.noMeasures }
        let header = rows.removeFirst().map(Column.init)

        let dateCol = header.firstIndex { ["date", "date time", "datetime", "timestamp", "measurement date", "measured at", "time of measurement"].contains($0.name) }
            ?? header.firstIndex { $0.name == "time" }
        guard let dateCol else { throw BodyImportError.noDateColumn }
        // Renpho and some others split date and time into two columns
        let timeCol = header[dateCol].name == "time" ? nil : header.firstIndex { $0.name == "time" }

        var fields: [(index: Int, field: Field)] = []
        for (i, c) in header.enumerated() where i != dateCol && i != timeCol {
            if let f = Field(c) { fields.append((i, f)) }
        }
        guard !fields.isEmpty else { throw BodyImportError.noMeasures }

        let parser = DateReader(timeZone: timeZone)
        var out: [BodyEntry] = []
        for row in rows {
            func cell(_ i: Int) -> String { i < row.count ? row[i].trimmingCharacters(in: .whitespaces) : "" }
            let dateText = timeCol.map { cell(dateCol) + " " + cell($0) } ?? cell(dateCol)
            guard let date = parser.date(dateText) else { continue }
            var raw: [(Field, Double, String?)] = []
            for (i, f) in fields {
                if let (v, unit) = value(cell(i), comma: delimiter == ";") { raw.append((f, v, unit)) }
            }
            out.append(contentsOf: entry(date: date, raw: raw).map { [$0] } ?? [])
        }
        guard !out.isEmpty else { throw BodyImportError.noMeasures }
        return out.sorted { $0.date < $1.date }
    }

    /// Turns one row's raw cells into snapshot units.
    static func entry(date: Date, raw: [(Field, Double, String?)]) -> BodyEntry? {
        func kg(_ v: Double, _ unit: String?) -> Double { unit.map(isPounds) == true ? v * 0.45359237 : v }
        var weight: Double?
        for (f, v, u) in raw where f.kind == .weight { weight = kg(v, u ?? f.unit) }
        var values: [BodyMeasure: Double] = [:]
        if let weight { values[.weight] = weight }
        for (f, v, cellUnit) in raw where f.kind != .weight {
            let unit = cellUnit ?? f.unit
            let isPercent = unit == "%"
            switch f.kind {
            case .bodyFat:
                if isPercent || (unit == nil && v < 70 && f.mass == false) { values[.bodyFat] = v / 100 }
                else if let w = weight, w > 0 { values[.bodyFat] = kg(v, unit) / w }
            case .muscleMass, .bodyWater, .boneMass, .leanMass:
                if isPercent { if let w = weight { values[f.kind] = values[f.kind] ?? w * v / 100 } }
                else { values[f.kind] = kg(v, unit) }   // a kg column wins over a percentage one
            default:
                values[f.kind] = v
            }
        }
        return values.isEmpty ? nil : BodyEntry(date: date, values: values)
    }

    /// The number in a cell and any unit written after it. "--", empty and zero mean no reading.
    static func value(_ s: String, comma: Bool) -> (Double, String?)? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if comma { t = t.replacingOccurrences(of: ",", with: ".") }
        let numberPart = t.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        guard let v = Double(numberPart), v > 0 else { return nil }
        let rest = t.dropFirst(numberPart.count).trimmingCharacters(in: .whitespaces).lowercased()
        return (v, rest.isEmpty ? nil : rest)
    }

    static func isPounds(_ unit: String) -> Bool { ["lb", "lbs", "pound", "pounds"].contains(unit) }

    /// A header split into its name and the unit in brackets: "Weight (kg)" is ("weight", "kg").
    struct Column {
        let name: String
        let unit: String?

        init(_ raw: String) {
            var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
            var unit: String?
            if let open = s.firstIndex(where: { $0 == "(" || $0 == "[" }) {
                unit = String(s[s.index(after: open)...]).trimmingCharacters(in: CharacterSet(charactersIn: ")] "))
                s = String(s[..<open])
            }
            s = s.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
            // "weight kg", "fat %" without brackets
            for u in ["kg", "lbs", "lb", "%", "kcal"] where s.hasSuffix(" " + u) {
                unit = u
                s = String(s.dropLast(u.count + 1))
            }
            name = s
            self.unit = unit.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Which measure a column holds, by the names scale apps use.
    struct Field {
        let kind: BodyMeasure
        let unit: String?
        let mass: Bool        // "fat mass" rather than "body fat"

        init?(_ c: Column) {
            let n = c.name
            unit = c.unit
            mass = n.contains("mass") && !n.contains("free") && !n.contains("lean")
            switch n {
            case "weight", "body weight", "weight value": kind = .weight
            case "body fat", "fat", "fat ratio", "body fat percentage", "body fat rate", "fat percentage", "fat mass", "body fat mass": kind = .bodyFat
            case "lean mass", "lean body mass", "fat-free mass", "fat free mass", "fat-free body weight", "fat free body weight", "ffm": kind = .leanMass
            case "muscle mass", "muscle", "skeletal muscle mass", "skeletal muscle", "muscle rate": kind = .muscleMass
            case "hydration", "body water", "water", "total body water", "water percentage", "body water percentage": kind = .bodyWater
            case "bone mass", "bone", "bones": kind = .boneMass
            case "bmr", "basal metabolic rate", "basal metabolism", "metabolism": kind = .bmr
            case "metabolic age", "body age": kind = .metabolicAge
            default:
                if n.contains("visceral") { kind = .visceralFat } else { return nil }
            }
        }
    }

    /// Scale apps write dates many ways. Day-first wins for ambiguous dates like 03/04, as in Europe; a US export
    /// with a day above 12 still reads correctly because day-first fails on it.
    struct DateReader {
        let formatters: [DateFormatter]
        let iso = ISO8601DateFormatter()

        init(timeZone: TimeZone) {
            let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd",
                           "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd", "yyyy.MM.dd HH:mm", "yyyy.MM.dd",
                           "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "dd.MM.yyyy HH:mm", "dd.MM.yyyy",
                           "dd-MM-yyyy HH:mm", "dd-MM-yyyy", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy h:mm a",
                           "MM/dd/yyyy", "MMM d, yyyy HH:mm", "MMM d, yyyy h:mm a", "MMM d, yyyy", "d MMM yyyy, HH:mm", "d MMM yyyy"]
            formatters = formats.map { f in
                let d = DateFormatter()
                d.locale = Locale(identifier: "en_US_POSIX")
                d.timeZone = timeZone
                d.dateFormat = f
                d.isLenient = false
                return d
            }
        }

        func date(_ s: String) -> Date? {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if let d = iso.date(from: t) { return d }
            return formatters.lazy.compactMap { $0.date(from: t) }.first
        }
    }
}

public enum BodyImport {
    /// Fills the snapshot from imported weigh-ins, first of each day. Weight, fat and lean mass only fill days
    /// Apple Health has nothing for, since most scale apps already write those there; the rest Apple Health has no
    /// types for, and fills days the Withings API left empty.
    public static func apply(_ entries: [BodyEntry], to s: inout HealthSnapshot) {
        func daily(_ m: BodyMeasure) -> [DailyValue] {
            Daily.first(entries.compactMap { e in e.values[m].map { Reading(date: e.date, value: $0) } })
        }
        s.weight = fill(s.weight, daily(.weight))
        s.bodyFat = fill(s.bodyFat, daily(.bodyFat))
        s.leanMass = fill(s.leanMass, daily(.leanMass))
        s.muscleMass = fill(s.muscleMass, daily(.muscleMass))
        s.bodyWater = fill(s.bodyWater, daily(.bodyWater))
        s.boneMass = fill(s.boneMass, daily(.boneMass))
        s.visceralFat = fill(s.visceralFat, daily(.visceralFat))
        s.bmr = fill(s.bmr, daily(.bmr))
        s.metabolicAge = fill(s.metabolicAge, daily(.metabolicAge))
    }

    /// Existing days stay; imported days are added where there was nothing. Oldest first.
    static func fill(_ base: [DailyValue], _ extra: [DailyValue]) -> [DailyValue] {
        let have = Set(base.map(\.date))
        return (base + extra.filter { !have.contains($0.date) }).sorted { $0.date < $1.date }
    }
}
