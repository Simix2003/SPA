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
    @Query(sort: \Expense.date) private var expenses: [Expense]

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
    @State private var showExportSheet = false
    @State private var exportTitle = ""
    @State private var exportText = ""

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
                        ForEach(filterableProjects) { p in
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prepareMonthlyExport()
                    } label: {
                        Label("Esporta mese", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Esporta mese")
                }
            }
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
        .sheet(isPresented: $showExportSheet) {
            ExportPreviewSheet(
                title: exportTitle,
                text: exportText,
                onClose: { showExportSheet = false }
            )
        }
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
    
    private var filterableProjects: [Project] {
        // Only show projects that actually have sessions in the current filtered range
        let items = filteredSessions.compactMap { $0.project }
        var unique: [Project] = []
        for p in items {
            if !unique.contains(where: { $0.id == p.id }) {
                unique.append(p)
            }
        }
        return unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                if let sel = selectedProject, !filterableProjects.contains(where: { $0.id == sel.id }) {
                    selectedProject = nil
                }
                Task { await CloudKitSyncEngine.shared.deleteWorkSessions(ids: [deletedID]) }
            }
            catch { errorMessage = "Eliminazione non riuscita: \(error.localizedDescription)" }
        }
    }

    // MARK: - Export
    private func prepareMonthlyExport() {
        let bounds = monthBounds()
        let monthSessions = allSessions
            .filter { bounds.contains($0.start) }
            .sorted { $0.start < $1.start }
        let monthExpenses = expenses
            .filter { bounds.contains($0.date) }
            .sorted { $0.date < $1.date }

        let monthFormatter = DateFormatter()
        monthFormatter.locale = .current
        monthFormatter.dateFormat = "LLLL yyyy"
        let title = monthFormatter.string(from: bounds.lowerBound).capitalized

        exportTitle = title
        exportText = makeMonthlyExportText(title: title, sessions: monthSessions, expenses: monthExpenses)
        showExportSheet = true
    }

    private func makeMonthlyExportText(title: String, sessions: [WorkSession], expenses: [Expense]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(sessions.count + expenses.count + 8)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateFormat = "dd-MM-yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.dateFormat = "HH:mm"

        let currencyFormatter = NumberFormatter()
        currencyFormatter.locale = .current
        currencyFormatter.numberStyle = .currency

        lines.append("Report mese \(title)")
        lines.append("")

        lines.append("Ore")
        if sessions.isEmpty {
            lines.append("Nessuna sessione registrata.")
        } else {
            var totalMinutes = 0
            for session in sessions {
                let dateString = dateFormatter.string(from: session.start)
                let startString = timeFormatter.string(from: session.start)
                let projectName = session.project?.name ?? "Senza commessa"

                if let end = session.end {
                    let endString = timeFormatter.string(from: end)
                    let minutes = payableMinutes(start: session.start, end: end, breakMin: session.breakMinutes, rule: session.rounding)
                    totalMinutes += minutes
                    let durationString = formatHoursForExport(minutes)
                    lines.append("\(dateString) \(startString) \(endString) \(durationString) \(projectName)")
                } else {
                    lines.append("\(dateString) \(startString) — — \(projectName) (aperta)")
                }
            }
            lines.append("Totale ore: \(formatHoursForExport(totalMinutes))")
        }

        lines.append("")
        lines.append("Spese")
        if expenses.isEmpty {
            lines.append("Nessuna spesa registrata.")
        } else {
            var totalAmount = Decimal.zero
            for expense in expenses {
                totalAmount += expense.amount
                let dateString = dateFormatter.string(from: expense.date)
                let amountString = currencyString(expense.amount, formatter: currencyFormatter)
                let projectName = expense.project?.name ?? "Senza commessa"
                var line = "\(dateString) \(amountString) \(expense.category) \(projectName)"
                if let note = expense.note, !note.isEmpty {
                    line.append(" - \(note)")
                }
                lines.append(line)
            }
            let totalString = currencyString(totalAmount, formatter: currencyFormatter)
            lines.append("Totale spese: \(totalString)")
        }

        return lines.joined(separator: "\n")
    }

    private func monthBounds(for date: Date = Date()) -> ClosedRange<Date> {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: comps) ?? date
        let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return start...end
    }

    private func formatHoursForExport(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    private func currencyString(_ amount: Decimal, formatter: NumberFormatter) -> String {
        formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
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
            }
            .navigationTitle("Modifica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(data)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(8)
                    }
                    .foregroundStyle(.white) // checkmark stays white
                    .glassEffect(.clear.tint(.blue)) // button glass tinted blue
                    .accessibilityLabel("Salva")
                }
            }
        }
    }
}

// MARK: - ExportPreviewSheet
private struct ExportPreviewSheet: View {
    let title: String
    let text: String
    let onClose: () -> Void

    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    Text(text.isEmpty ? "Nessun dato disponibile per questo mese." : text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }

                HStack {
                    ShareLink(item: text.isEmpty ? "" : text) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                    .disabled(text.isEmpty)

                    Spacer()

                    Button {
                        copyToPasteboard(text)
                        withAnimation(.spring(duration: 0.3)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.spring(duration: 0.3)) { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copiato" : "Copia", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    .disabled(text.isEmpty)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { onClose() }
                }
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value.isEmpty ? nil : value
        #endif
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
