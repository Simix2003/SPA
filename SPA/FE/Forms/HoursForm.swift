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
    var breakMin: Int = 0
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Commessa
                GroupBox("Commessa") {
                    TextField("Cliente/Commessa", text: $data.projectName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .textContentType(.organizationName)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .project)
                        .padding(.vertical, 8)
                }
                // Quick action if there's an open session (to support multi-commesse workflows)
                if hasOpenSession {
                    GroupBox("Sessione aperta") {
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
                GroupBox("Tipo") {
                    Picker("Tipo", selection: $data.type) {
                        ForEach(sortedTypes) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu) // menu works well inside sheets; change to .segmented if you prefer and reduce options
                }
                // Orari
                GroupBox("Orari") {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Inizio", selection: $data.start, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                        Toggle("Imposta fine", isOn: $data.hasEnd)
                        if data.hasEnd {
                            DatePicker("Fine", selection: $data.end, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                        }
                        HStack {
                            Text("Pausa:")
                            Spacer()
                            Stepper(value: $data.breakMin, in: 0...180, step: 5) {
                                Text("\(data.breakMin) min")
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Arrotondamento") {
                    Picker("", selection: $data.rounding) {
                        ForEach(RoundingRule.allCases, id: \.self) { r in
                            Text(String(describing: r)).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Note
                GroupBox("Note") {
                    TextField("Aggiungi nota", text: $data.note, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .note)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .frame(minHeight: 320)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Fine") { focusedField = nil }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}
