//
//  HistoryView.swift
//  Test
//
//  Created by Simone Paparo on 24/09/25.
//


import SwiftUI
import SwiftData

// MARK: - HistoryView
struct HistoryView: View {
    @Environment(\.modelContext) private var context

    // All sessions & projects (we’ll filter in memory for MVP)
    @Query(sort: \WorkSession.start, order: .reverse) private var allSessions: [WorkSession]
    @Query(sort: \Project.name) private var projects: [Project]

    // Filters
    enum RangeFilter: String, CaseIterable, Identifiable {
        case week = "Settimana", month = "Mese", all = "Tutto"
        var id: String { rawValue }
    }
    @State private var range: RangeFilter = .month
    @State private var selectedProject: Project?

    // Edit state
    @State private var editing: WorkSession?
    @State private var editData = HoursInput()
    @State private var showEdit = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                // Filters row
                HStack {
                    Picker("", selection: $range) {
                        ForEach(RangeFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Menu {
                        Button("Tutte le commesse") { selectedProject = nil }
                        Divider()
                        ForEach(projects) { p in
                            Button(p.name) { selectedProject = p }
                        }
                    } label: {
                        Label(selectedProject?.name ?? "Tutte", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .padding(.horizontal)

                if groupedSessions.isEmpty {
                    ContentUnavailableView(
                        "Nessuna sessione",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Aggiungi ore dalla Home con il tasto +")
                    )
                    .padding(.top, 24)
                } else {
                    List {
                        ForEach(sortedSectionKeys, id: \.self) { day in
                            Section(header: Text(day.formatted(.dateTime.day().month().year()))) {
                                ForEach(groupedSessions[day] ?? []) { s in
                                    Button {
                                        beginEdit(s)
                                    } label: {
                                        HistoryRow(session: s)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteSession(s)
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                    }
                                }

                                // Day total
                                HStack {
                                    Spacer()
                                    Text("Totale giorno: \(minutesToHhMm(totalMinutes(for: groupedSessions[day] ?? [])))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Storico")
        }
        .sheet(isPresented: $showEdit) {
            EditSessionSheet(
                data: $editData,
                availableProjects: projects.map(\.name),
                onSave: saveEdit,
                onCancel: { showEdit = false }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Errore", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    // MARK: - Derived data
    private var filteredSessions: [WorkSession] {
        let rangeBounds = currentRangeBounds()
        return allSessions.filter { s in
            (s.start >= rangeBounds.lowerBound && s.start <= rangeBounds.upperBound)
            && (selectedProject == nil || s.project?.id == selectedProject?.id)
        }
    }

    private var groupedSessions: [Date: [WorkSession]] {
        Dictionary(grouping: filteredSessions) { startOfDay(for: $0.start) }
    }

    private var sortedSectionKeys: [Date] {
        groupedSessions.keys.sorted(by: >)
    }

    // MARK: - Actions
    private func beginEdit(_ s: WorkSession) {
        editing = s
        editData = HoursInput(
            projectName: s.project?.name ?? "",
            start: s.start,
            end: s.end ?? s.start,
            hasEnd: (s.end != nil),
            breakMin: s.breakMinutes,
            note: s.note ?? "",
            rounding: s.rounding
        )
        showEdit = true
    }

    private func saveEdit(_ input: HoursInput) {
        guard let s = editing else { return }
        // Validate
        if input.hasEnd, input.end < input.start {
            errorMessage = "L'orario di fine non può essere precedente all'inizio."
            return
        }

        do {
            // Resolve/create project
            if !input.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let name = input.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
                let fd = FetchDescriptor<Project>(predicate: #Predicate { $0.name == name })
                if let existing = try? context.fetch(fd).first {
                    s.project = existing
                } else {
                    let p = Project(name: name)
                    p.updatedAt = Date()
                    context.insert(p)
                    try context.save()
                    s.project = p
                }
            } else {
                s.project = nil
            }

            s.start = input.start
            if input.hasEnd {
                s.end = input.end
                s.state = .closed
            } else {
                s.end = nil
                s.state = .open
            }
            s.breakMinutes = max(0, input.breakMin)
            s.note = input.note.isEmpty ? nil : input.note
            s.rounding = input.rounding
            s.updatedAt = Date()

            try context.save()
            // Mirror to CloudKit (Phase 1: create/update only)
            Task { await CloudKitSyncEngine.shared.pushAll(context: context) }
            showEdit = false
        } catch {
            errorMessage = "Impossibile salvare le modifiche: \(error.localizedDescription)"
        }
    }

    private func deleteSession(_ s: WorkSession) {
        let deletedID = s.id
        withAnimation {
            context.delete(s)
            do { try context.save()
                Task { await CloudKitSyncEngine.shared.deleteWorkSessions(ids: [deletedID]) }
            }
            catch { errorMessage = "Eliminazione non riuscita: \(error.localizedDescription)" }
        }
    }

    // MARK: - Helpers: grouping, totals, formatting
    private func currentRangeBounds() -> ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .week:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            let end = cal.date(byAdding: .day, value: 7, to: start)?.addingTimeInterval(-1) ?? now
            return start...end
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps) ?? now
            let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? now
            return start...end
        case .all:
            // Very wide range
            return Date(timeIntervalSince1970: 0)...Date.distantFuture
        }
    }

    private func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func totalMinutes(for daySessions: [WorkSession]) -> Int {
        daySessions.reduce(0) { acc, s in
            guard let end = s.end else { return acc }
            return acc + payableMinutes(start: s.start, end: end, breakMin: s.breakMinutes, rule: s.rounding)
        }
    }

    private func minutesToHhMm(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%dh %02d'", h, m)
    }
}

// MARK: - HistoryRow
private struct HistoryRow: View {
    let session: WorkSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Leading badge with project initials
            Circle()
                .fill(.quaternary)
                .frame(width: 30, height: 30)
                .overlay(
                    Text(initials(from: session.project?.name ?? ""))
                        .font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.project?.name ?? "Senza commessa")
                    .font(.body).fontWeight(.semibold)
                Text(timeRangeText(session))
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Spacer()

            Text(durationText(session))
                .font(.callout)
                .monospacedDigit()
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }

    private func timeRangeText(_ s: WorkSession) -> String {
        let timeFmt = Date.FormatStyle.dateTime.hour().minute()
        if let end = s.end {
            return "\(s.start.formatted(timeFmt)) → \(end.formatted(timeFmt))"
        } else {
            return "\(s.start.formatted(timeFmt)) → — (aperta)"
        }
    }

    private func durationText(_ s: WorkSession) -> String {
        guard let end = s.end else { return "—" }
        let mins = payableMinutes(start: s.start, end: end, breakMin: s.breakMinutes, rule: s.rounding)
        let h = mins / 60, m = mins % 60
        return String(format: "%d:%02d", h, m)
    }
}

// MARK: - EditSessionSheet
private struct EditSessionSheet: View {
    @Binding var data: HoursInput
    let availableProjects: [String]
    let onSave: (HoursInput) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Commessa") {
                    // Simple text field; you can swap with a Picker if you prefer strict selection
                    TextField("Cliente/Commessa", text: $data.projectName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Orari") {
                    DatePicker("Inizio", selection: $data.start, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Imposta fine", isOn: $data.hasEnd)
                    if data.hasEnd {
                        DatePicker("Fine", selection: $data.end, in: data.start..., displayedComponents: [.date, .hourAndMinute])
                    }
                    Stepper(value: $data.breakMin, in: 0...180, step: 5) {
                        Text("Pausa: \(data.breakMin) min")
                    }
                }

                Section("Arrotondamento") {
                    Picker("Regola", selection: $data.rounding) {
                        ForEach(RoundingRule.allCases, id: \.self) { r in
                            Text(ruleLabel(r)).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Note") {
                    TextField("Aggiungi nota", text: $data.note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Modifica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { onSave(data) }
                }
            }
        }
    }

    private func ruleLabel(_ r: RoundingRule) -> String {
        switch r {
        case .off: return "Off"
        case .nearest5: return "5'"
        case .nearest15: return "15'"
        case .nearest30: return "30'"
        }
    }
}

// MARK: - Duration helpers (copy here so the file is self-contained)
private func rounded(_ date: Date, rule: RoundingRule) -> Date {
    switch rule {
    case .off: return date
    case .nearest5:  return date.rounded(to: 5*60)
    case .nearest15: return date.rounded(to: 15*60)
    case .nearest30: return date.rounded(to: 30*60)
    }
}
private extension Date {
    func rounded(to step: TimeInterval) -> Date {
        let t = timeIntervalSince1970
        let r = (t / step).rounded() * step
        return Date(timeIntervalSince1970: r)
    }
}
private func payableMinutes(start: Date, end: Date, breakMin: Int, rule: RoundingRule) -> Int {
    let s = rounded(start, rule: rule)
    let e = rounded(end, rule: rule)
    return max(0, Int(e.timeIntervalSince(s)/60) - max(0, breakMin))
}
