import SwiftUI
// MARK : HoursInput

struct HoursInput {
    var projectName: String = ""
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

    @FocusState private var focusedField: Field?
    private enum Field: Hashable {
        case project, note
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
