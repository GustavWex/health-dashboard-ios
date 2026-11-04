import SwiftUI
import SwiftData
import HealthCore

/// Tag what happened on a day. Opened from the Info tab.
struct JournalView: View {
    let model: DashboardModel
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
    @State private var day = Calendar.current.date(byAdding: .day, value: -1,
                                                    to: Calendar.current.startOfDay(for: .now))!

    var body: some View {
            Form {
                Section {
                    DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
                    ForEach(JournalTags.all, id: \.self) { tag in
                        Toggle(tag, isOn: binding(for: tag))
                    }
                } header: {
                    Text("What happened this day?")
                } footer: {
                    Text("Each tag is compared with your recovery the next morning.")
                }

                Section("Effect on next-day recovery") {
                    let impacts = ImpactEngine.analyze(
                        entries: entries.map { (day: $0.day, tags: $0.tags) },
                        scores: model.scoreHistory
                    )
                    if impacts.isEmpty {
                        Text("Log a tag on at least 3 days to see its effect.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(impacts) { i in
                        HStack {
                            Text(i.tag)
                            Spacer()
                            Text(String(format: "%+.0f", i.delta))
                                .monospacedDigit()
                                .fontWeight(.semibold)
                                .foregroundStyle(i.delta >= 0 ? Zone.push.color : Zone.recover.color)
                            Text("\(i.count) days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
            .ambientList()
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func entry(for date: Date) -> JournalEntry? {
        let d = Calendar.current.startOfDay(for: date)
        return entries.first { $0.day == d }
    }

    private func binding(for tag: String) -> Binding<Bool> {
        Binding(
            get: { entry(for: day)?.tags.contains(tag) ?? false },
            set: { isOn in
                let d = Calendar.current.startOfDay(for: day)
                let e: JournalEntry
                if let existing = entry(for: d) {
                    e = existing
                } else {
                    e = JournalEntry(day: d)
                    context.insert(e)
                }
                if isOn {
                    if !e.tags.contains(tag) { e.tags.append(tag) }
                } else {
                    e.tags.removeAll { $0 == tag }
                }
            }
        )
    }
}
