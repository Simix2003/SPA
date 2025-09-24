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
    @State private var hasOpenSession = false
    @State private var currentOpenProjectName: String? = nil
    @State private var errorMessage: String?
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
            .onAppear { refreshOpenSessionContext() }

            Group {
                switch selected {
                case .hours:
                    HoursForm(
                        data: $hours,
                        hasOpenSession: hasOpenSession,
                        currentOpenProjectName: currentOpenProjectName,
                        onSwitchRequested: {
                            do {
                                let store = WorkSessionStore(context)
                                // Resolve or create Project from typed name (optional)
                                var target: Project?
                                let name = hours.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !name.isEmpty {
                                    let fd = FetchDescriptor<Project>(predicate: #Predicate { $0.name == name })
                                    if let existing = try? context.fetch(fd).first {
                                        target = existing
                                    } else {
                                        let p = Project(name: name)
                                        context.insert(p)
                                        try context.save()
                                        target = p
                                    }
                                }
                                _ = try store.switchOpenSession(to: target, rounding: hours.rounding, at: Date())
                                // CloudKit push after switch
                                Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
                                onClose()
                            } catch {
                                errorMessage = "Switch non riuscito: \(error.localizedDescription)"
                            }
                        }
                    )
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
                        if hours.hasEnd && hours.end < hours.start {
                            errorMessage = "L'orario di fine non può precedere l'inizio."
                            return
                        }
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
                                Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
                            } else {
                                var s = try store.startSession(at: hours.start, project: project, rounding: hours.rounding)
                                s.note = hours.note.isEmpty ? nil : hours.note
                                s.breakMinutes = max(0, hours.breakMin)
                                try context.save()
                                Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
                            }
                            onClose()
                        } catch {
                            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
                        }
                    case .expenses:
                        // handled by ExpensesForm's onSubmit closure
                        break
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .alert("Errore", isPresented: .constant(errorMessage != nil)) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func refreshOpenSessionContext() {
        let store = WorkSessionStore(context)
        if let open = try? store.currentOpenSession() {
            hasOpenSession = true
            currentOpenProjectName = open.project?.name
        } else {
            hasOpenSession = false
            currentOpenProjectName = nil
        }
    }
}
