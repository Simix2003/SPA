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
    var onClose: () -> Void
    enum Tab: String, CaseIterable, Identifiable { case hours = "Ore", expenses = "Spese"; var id: String { rawValue } }
    @State private var selected: Tab = .hours
    @Environment(\.modelContext) private var context
    @State private var hours = HoursInput()
    @State private var hasOpenSession = false
    @State private var currentOpenProjectName: String? = nil
    @State private var errorMessage: String?
    // Dismiss keyboard before closing the sheet to avoid RTIInputSystemClient warnings
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
            // Refresh open-session context when sheet appears
            }
            .onAppear { refreshOpenSessionContext() }

            TabView(selection: $selected) {
                // Tab 1: Ore
                HoursForm(
                    data: $hours,
                    hasOpenSession: hasOpenSession,
                    currentOpenProjectName: currentOpenProjectName,
                    onSwitchRequested: {
                        do {
                            let store = WorkSessionStore(context)
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
                            Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
                            dismissKeyboard()
                            onClose()
                        } catch let ws as WorkSessionError {
                            switch ws {
                            case .overlapDetected:
                                errorMessage = "Non posso chiudere: l'intervallo si sovrappone a un'altra sessione."
                            case .noOpenSession:
                                errorMessage = "Nessuna sessione aperta da chiudere."
                            }
                        } catch {
                            let ns = error as NSError
                            print("[Switch] error:", ns)
                            errorMessage = "Switch non riuscito (\(ns.domain) \(ns.code))\n\(ns.localizedDescription)\n\(ns.userInfo)"
                        }
                    }
                )
                .tabItem { Label("Ore", systemImage: "clock") }
                .tag(Tab.hours)
                
                // Tab 2: Spese
                ExpensesForm { input in
                    // TODO: persist with SwiftData when Expense model is ready
                    onClose()
                }
                .tabItem { Label("Spese", systemImage: "creditcard") }
                .tag(Tab.expenses)
            }

        }
        .navigationTitle(selected == .hours ? "Registra ore" : "Spese")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .toolbarBackground(.regularMaterial, for: .tabBar)
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()

                Button {
                    handleSave()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .semibold))
                        .padding(14)
                }
                .glassEffect(.regular.tint(.blue), in: Circle())
                .foregroundStyle(.white)
                .buttonBorderShape(.circle)
                .scrollEdgeEffectStyle(.hard, for: .top)
                .accessibilityLabel("Salva")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
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

    private func handleSave() {
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
                    dismissKeyboard()
                } else {
                    let s = try store.startSession(at: hours.start, project: project, rounding: hours.rounding)
                    s.note = hours.note.isEmpty ? nil : hours.note
                    s.breakMinutes = max(0, hours.breakMin)
                    try context.save()
                    Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
                    dismissKeyboard()
                }
                // Debug count
                do {
                    let count = try context.fetch(FetchDescriptor<WorkSession>()).count
                    print("[Save] WorkSession count now:", count)
                } catch { print("[Save] count fetch failed:", error) }
                onClose()
            } catch let ws as WorkSessionError {
                switch ws {
                case .overlapDetected:
                    errorMessage = "Salvataggio non riuscito: intervallo sovrapposto a un'altra sessione."
                case .noOpenSession:
                    errorMessage = "Salvataggio non riuscito: nessuna sessione aperta da chiudere."
                }
            } catch {
                let ns = error as NSError
                print("[Save] error:", ns)
                errorMessage = "Salvataggio non riuscito (\(ns.domain) \(ns.code))\n\(ns.localizedDescription)\n\(ns.userInfo)"
            }
        case .expenses:
            // No-op: ExpensesForm handles its own save internally for now
            break
        }
    }
}
