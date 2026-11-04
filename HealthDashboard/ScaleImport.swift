import SwiftUI
import HealthCore

/// Scale app exports, kept as the raw files in Application Support so a parser fix applies to old imports too.
/// Each import is kept, so exports from different scales or apps add up. Stays on device.
enum BodyStore {
    static var folder: URL { URL.applicationSupportDirectory.appendingPathComponent("body", isDirectory: true) }

    static var files: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "csv" } ?? []
    }

    static func load() -> [BodyEntry] {
        files.flatMap { url -> [BodyEntry] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return (try? BodyCSV.parse(text)) ?? []
        }
        .sorted { $0.date < $1.date }
    }

    /// Parses first, so a wrong file is never kept. A file with the same name replaces the earlier import.
    static func importFile(at source: URL) throws -> [BodyEntry] {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: source, encoding: .utf8)
        let entries = try BodyCSV.parse(text)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = source.deletingPathExtension().lastPathComponent + ".csv"
        try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return entries
    }

    static func remove() { try? FileManager.default.removeItem(at: folder) }

    static func message(for error: Error) -> String {
        switch error as? BodyImportError {
        case .noDateColumn?: "No date column found. The file needs a column named Date or Time."
        case .noMeasures?: "No weight or body composition columns found in this file."
        case nil: "Couldn't read the file: \(error.localizedDescription)"
        }
    }

    /// Which measures the imports hold, for the summary line.
    static func summary(_ entries: [BodyEntry]) -> String {
        let names: [BodyMeasure: String] = [.weight: "weight", .bodyFat: "body fat", .leanMass: "lean mass",
                                            .muscleMass: "muscle", .bodyWater: "water", .boneMass: "bone",
                                            .visceralFat: "visceral fat", .bmr: "BMR", .metabolicAge: "metabolic age"]
        let present = Set(entries.flatMap { $0.values.keys })
        return BodyMeasure.allCases.filter(present.contains).compactMap { names[$0] }.joined(separator: ", ")
    }
}

struct ScaleImportSection: View {
    let model: DashboardModel
    @State private var picking = false
    @State private var message: String?
    @State private var entries = BodyStore.load()

    var body: some View {
        Section {
            Button("Import scale export") { picking = true }
            if !entries.isEmpty {
                LabeledContent("Weigh-ins", value: "\(entries.count)")
                if let first = entries.first, let last = entries.last {
                    LabeledContent("Range", value: first.date.formatted(.dateTime.day().month().year()) + " to "
                                   + last.date.formatted(.dateTime.day().month().year()))
                }
                Text(BodyStore.summary(entries)).font(.footnote).foregroundStyle(.secondary)
                Button("Remove imported scale data", role: .destructive) {
                    BodyStore.remove()
                    entries = []
                    Task { await model.refresh() }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Other smart scales")
        } footer: {
            Text("Weight and body fat come from Apple Health for any scale whose app writes there. For muscle, water, bone and visceral fat, export a CSV from your scale's app (Withings, Renpho, Eufy, Garmin, Fitbit, Zepp and others) and pick it here. Days Apple Health already has are kept.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: true) { result in
            do {
                var count = 0
                for url in try result.get() { count += try BodyStore.importFile(at: url).count }
                message = "Imported \(count) weigh-ins."
                entries = BodyStore.load()
                Task { await model.refresh() }
            } catch {
                message = BodyStore.message(for: error)
            }
        }
    }
}
