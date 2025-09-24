import SwiftUI

// MARK: - SessionType (Tipo)
enum SessionType: String, Codable, CaseIterable, Identifiable {
    case ferie = "Ferie"
    case intervento = "Intervento"
    case malattia = "Malattia"
    case permesso = "Permesso"
    case permessoNonRetribuito = "Permesso non Retribuito"
    case trasferta = "Trasferta"
    case ufficio = "Ufficio"
    case viaggio = "Viaggio"
    case viaggioTrasferta = "Viaggio + Trasferta"

    var id: String { rawValue }
    var displayName: String { rawValue }
}
// MARK : HoursInput

struct HoursInput {
    var projectName: String = ""
    var type: SessionType = .ufficio
    var start: Date = .init()
    var end: Date = .init()
    var hasEnd: Bool = true
    var breakMin: Int = 60
    var note: String = ""
    var rounding: RoundingRule = .nearest15
}

// MARK: - HoursForm
struct HoursForm: View {
    @Binding var data: HoursInput
    // Optional context provided by the parent (e.g., AddSheetView)
    var hasOpenSession: Bool = false
    var currentOpenProjectName: String? = nil
    var onSwitchRequested: (() -> Void)? = nil

    @FocusState private var focusedField: Field?
    private enum Field: Hashable {
        case project, note
    }
    private var sortedTypes: [SessionType] {
        SessionType.allCases.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }
    private var roundingTitle: [RoundingRule:String] {
        [
            .off: "Nessuno",
            .nearest5: "5 min",
            .nearest15: "15 min",
            .nearest30: "30 min"
        ]
    }
    private let lunchPresets: [Int] = [0, 15, 30, 45, 60, 90]

    private var durationText: String {
        guard data.hasEnd else { return "Durata: —" }
        let total = max(0, Int(data.end.timeIntervalSince(data.start) / 60))
        let work = max(0, total - max(0, data.breakMin))
        let h = work / 60
        let m = work % 60
        return "Durata: \(h)h \(m)m  •  Pausa \(data.breakMin)m"
    }
    private func setEnd(forWorkMinutes minutes: Int) {
        let delta = minutes + max(0, data.breakMin)
        if let newEnd = Calendar.current.date(byAdding: .minute, value: delta, to: data.start) {
            data.end = newEnd
            data.hasEnd = true
        }
    }

    var body: some View {
        Form {
            // Commessa
            Section("Commessa") {
                TextField("Cliente/Commessa", text: $data.projectName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .project)
            }

            // Quick action if there's an open session (multi-commesse)
            if hasOpenSession {
                Section("Sessione aperta") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("C'è una sessione attiva\(currentOpenProjectName != nil ? " per \(currentOpenProjectName!)" : "")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button {
                            onSwitchRequested?()
                        } label: {
                            let target = data.projectName.isEmpty ? "nuova commessa" : data.projectName
                            Label("Chiudi e passa a \(target)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Tipo
            Section("Tipo") {
                Picker("Tipo", selection: $data.type) {
                    ForEach(sortedTypes) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }

            // Orari
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


            // Note
            Section("Note") {
                TextField("Aggiungi nota", text: $data.note, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .note)
            }
        }
        .padding(.top, 60)
        .scrollDismissesKeyboard(.interactively)
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
