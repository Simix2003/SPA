//
//  AddSheetView.swift
//  Test
//
//  Created by Simone Paparo on 24/09/25.
//
import SwiftUI
import SwiftData

// MARK: - AddSheetView (temporary scaffold — move to AddSheetView.swift later)
struct AddSheetView: View {
    enum Tab: String, CaseIterable, Identifiable { case hours = "Ore", expenses = "Spese"; var id: String { rawValue } }
    @State private var selected: Tab = .hours
    @Environment(\.modelContext) private var context
    @State private var hours = HoursInput()
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Picker("", selection: $selected) {
                ForEach(Tab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                switch selected {
                case .hours:
                    HoursForm(data: $hours)
                case .expenses:
                    ExpensesForm { input in
                        // TODO: persist with SwiftData when Expense model is ready
                        // e.g., create Expense from `input` and save.
                        onClose()
                    }
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Chiudi") { onClose() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Salva") {
                    switch selected {
                    case .hours:
                        do {
                            let store = WorkSessionStore(context)
                            // Resolve or create Project from typed name (optional)
                            var project: Project?
                            let name = hours.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                let fd = FetchDescriptor<Project>(predicate: #Predicate { $0.name == name })
                                if let existing = try? context.fetch(fd).first {
                                    project = existing
                                } else {
                                    let p = Project(name: name)
                                    context.insert(p)
                                    try context.save()
                                    project = p
                                }
                            }
                            // Create closed or open session based on hasEnd
                            if hours.hasEnd {
                                try store.createClosedSession(
                                    start: hours.start,
                                    end: hours.end,
                                    breakMinutes: hours.breakMin,
                                    project: project,
                                    note: hours.note.isEmpty ? nil : hours.note,
                                    rounding: hours.rounding
                                )
                            } else {
                                var s = try store.startSession(at: hours.start, project: project, rounding: hours.rounding)
                                s.note = hours.note.isEmpty ? nil : hours.note
                                s.breakMinutes = max(0, hours.breakMin)
                                try context.save()
                            }
                            onClose()
                        } catch {
                            // TODO: present an alert if you want
                            print("Save error: \(error)")
                        }
                    case .expenses:
                        // handled by ExpensesForm's onSubmit closure
                        break
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
