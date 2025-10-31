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
    @State private var exportStatus: ExportStatus?
    @State private var exportWorkbookURL: URL?

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
            if let status = exportStatus {
                ExportPreviewSheet(
                    title: exportTitle,
                    status: status,
                    fileURL: exportWorkbookURL,
                    onClose: {
                        exportStatus = nil
                        exportWorkbookURL = nil
                        showExportSheet = false
                    }
                )
            } else {
                ProgressView()
                    .padding()
            }
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
        exportWorkbookURL = nil
        exportStatus = nil

        do {
            let result = try MonthlyExportWorkbook().makeWorkbook(title: title, sessions: monthSessions, expenses: monthExpenses)
            exportWorkbookURL = result.fileURL
            let summary = exportSummary(sessionCount: result.sessionCount, expenseCount: result.expenseCount)
            exportStatus = .success(message: "Esportazione completata", detail: summary)
        } catch {
            exportWorkbookURL = nil
            let message: String
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                message = description
            } else {
                message = error.localizedDescription
            }
            exportStatus = .failure(message: "Esportazione non riuscita", detail: message)
        }

        showExportSheet = true
    }

    private func exportSummary(sessionCount: Int, expenseCount: Int) -> String {
        let sessionText = sessionCount == 1 ? "1 sessione" : "\(sessionCount) sessioni"
        let expenseText = expenseCount == 1 ? "1 spesa" : "\(expenseCount) spese"
        return "\(sessionText) • \(expenseText)"
    }

    private func monthBounds(for date: Date = Date()) -> ClosedRange<Date> {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: comps) ?? date
        let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return start...end
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

// MARK: - Export preview helpers
private enum ExportStatus {
    case success(message: String, detail: String?)
    case failure(message: String, detail: String?)

    var message: String {
        switch self {
        case .success(let message, _), .failure(let message, _):
            return message
        }
    }

    var detail: String? {
        switch self {
        case .success(_, let detail), .failure(_, let detail):
            return detail
        }
    }

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private struct ExportPreviewSheet: View {
    let title: String
    let status: ExportStatus
    let fileURL: URL?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                statusHeader

                if status.isSuccess, let url = fileURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(url.lastPathComponent, systemImage: "doc")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ShareLink(
                            item: url,
                            subject: Text("Report \(title)"),
                            message: Text("In allegato il workbook per \(title)."),
                            preview: SharePreview(Text(title), image: Image(systemName: "tablecells"))
                        ) {
                            Label("Condividi workbook", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(status.tint)
                    }

                    Text("Scegli Mail per allegare subito il file e spedirlo al cliente.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Chiudi e riprova l'esportazione se il problema persiste.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { onClose() }
                }
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: status.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(status.tint, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(status.message)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let detail = status.detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
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
