import SwiftUI
import Charts
import HealthCore

/// Exports from the bedroom monitor, kept as files in Application Support/room and merged on load. The monitor
/// pushes to InfluxDB; its daily CSV export is what comes in here for now. Stays on device.
enum RoomStore {
    static var folder: URL { URL.applicationSupportDirectory.appendingPathComponent("room", isDirectory: true) }

    static func load() -> [RoomReading] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return RoomCSV.merge(files.compactMap { (try? String(contentsOf: $0, encoding: .utf8)).flatMap { try? RoomCSV.parse($0) } })
    }

    /// Checks each file parses before keeping it, so a wrong file never ends up in the data.
    static func importFiles(_ urls: [URL]) throws -> Int {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            count += try RoomCSV.parse(text).count
            try Data(text.utf8).write(to: folder.appendingPathComponent(url.lastPathComponent), options: [.atomic, .completeFileProtection])
        }
        return count
    }

    static func removeAll() { try? FileManager.default.removeItem(at: folder) }
}

/// The bedroom: last night's CO2 curve, the morning air change rate, nights over time and the sensor checklist.
struct BedroomView: View {
    let model: DashboardModel
    @State private var picking = false
    @State private var message: String?

    private var s: HealthSnapshot { model.snapshot }
    private var nights: [RoomNight] { RoomEngine.nights(s.room, sleep: s.sleep) }
    private var airChanges: [AirChange] { RoomEngine.airChanges(s.room, sleep: s.sleep.suffix(14).map { $0 }) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let last = nights.last {
                    Card(title: "Last night's air", systemImage: "wind") {
                        RoomNightChart(night: last)
                        HStack {
                            MetricTile(label: "Average CO2", value: fmt(last.co2Mean, 0, " ppm"))
                            MetricTile(label: "At wake-up", value: fmt(last.co2AtWake, 0, " ppm"))
                            MetricTile(label: "Over 2,000", value: "\(Int(last.minutesAbove2000.rounded())) min")
                        }
                        HStack {
                            MetricTile(label: "Temperature", value: fmt(last.temperatureMean, 1, " °C"))
                            MetricTile(label: "Humidity", value: fmt(last.humidityMean, 0, "%"),
                                       detail: (last.humidityMin ?? 100) < RoomEngine.dry ? "dipped under 30%" : nil)
                        }
                        Text(verdict(last)).font(.subheadline)
                    }
                    if let a = airChanges.first {
                        Card(title: "Air change rate", systemImage: "arrow.triangle.2.circlepath") {
                            HStack {
                                MetricTile(label: "This morning", value: String(format: "%.2f /h", a.ach), detail: "air changes per hour")
                                MetricTile(label: "Room forgets in", value: String(format: "%.1f h", 1 / a.ach), detail: "time constant 1/ACH")
                                MetricTile(label: "Outdoor fit", value: String(format: "%.0f ppm", a.outdoor), detail: "should be near 420")
                            }
                            Text("Fitted from how fast CO2 fell after you got up. At this rate, airing out before bed barely changes the morning: what matters is air exchange during the night.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Card(title: "Nights", systemImage: "moon.stars") {
                        Chart(nights.suffix(30)) { n in
                            if let m = n.co2AtWake {
                                BarMark(x: .value("Night", n.date, unit: .day), y: .value("ppm", m))
                                    .foregroundStyle(m > RoomEngine.sealed ? Palette.caution.gradient : Palette.air.gradient)
                            }
                            RuleMark(y: .value("Sealed", RoomEngine.sealed))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        }
                        .frame(height: 150)
                        Text("CO2 at wake-up per night. Amber is over 2,000 ppm, where the DTU Campus Village study found worse sleep and next-day performance.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Card(title: "Bedroom air", systemImage: "wind") {
                        Text("No readings yet. Import the monitor's CSV export: one row per sample with time, co2, temperature, humidity and lux, or InfluxDB's own CSV export.")
                            .font(.subheadline)
                    }
                }
                Card(title: "Data", systemImage: "square.and.arrow.down") {
                    Button("Import CSV export") { picking = true }
                    if !s.room.isEmpty {
                        Text("\(s.room.count) readings from \(s.room.first!.date.formatted(.dateTime.day().month())) to \(s.room.last!.date.formatted(.dateTime.day().month()))")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Remove imported data", role: .destructive) {
                            RoomStore.removeAll()
                            Task { await model.refresh() }
                        }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Card(title: "Before trusting the numbers", systemImage: "checklist") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Automatic baseline calibration off on the SCD41, or a forced recalibration outdoors at 420 ppm.", systemImage: "1.circle")
                        Label("24 hours of warm-up before the first night counts.", systemImage: "2.circle")
                        Label("Away from the head of the bed; breath on the sensor fakes a curve.", systemImage: "3.circle")
                        Label("Sensor on a 10 cm cable from the board, with a fixed temperature offset checked against a thermometer.", systemImage: "4.circle")
                    }
                    .font(.footnote)
                }
            }
            .padding()
        }
        .background(AmbientBackground())
        .navigationTitle("Bedroom")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: true) { result in
            do {
                let n = try RoomStore.importFiles(result.get())
                message = "Imported \(n) readings."
                Task { await model.refresh() }
            } catch {
                message = "Couldn't read that file as a room export."
            }
        }
    }

    private func verdict(_ n: RoomNight) -> String {
        guard let wake = n.co2AtWake else { return "No CO2 readings during the night." }
        if wake > RoomEngine.sealed { return "CO2 climbed past 2,000 ppm by morning: the room was effectively sealed. A latched window, open vents or a door ajar during the night is the fix." }
        if wake > RoomEngine.wellVentilated { return "CO2 rose above 1,000 ppm but stayed under 2,000: some air exchange, not much." }
        return "CO2 stayed under 1,000 ppm: ventilation looks adequate, so morning grogginess is likely something else."
    }
}

/// CO2 over one night with the 1,000 and 2,000 ppm lines.
struct RoomNightChart: View {
    let night: RoomNight
    @State private var selected: Date?

    private var points: [DailyValue] { night.readings.compactMap { r in r.co2.map { DailyValue(date: r.date, value: $0) } } }

    var body: some View {
        let pick = ChartSelection.nearest(points, to: selected)
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Time", p.date), y: .value("ppm", p.value))
                    .foregroundStyle(Palette.air)
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("1,000", RoomEngine.wellVentilated)).foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
            RuleMark(y: .value("2,000", RoomEngine.sealed)).foregroundStyle(Palette.caution)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .annotation(position: .top, alignment: .leading) { Text("2,000").font(.caption2).foregroundStyle(Palette.caution) }
            if let pick {
                RuleMark(x: .value("Selected", pick.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(Int(pick.value)) ppm").font(.caption.weight(.bold)).monospacedDigit()
                            Text(pick.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 170)
        .padding(.top, 20)
    }
}
