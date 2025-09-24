//
//  ExpenseInput.swift
//  Test
//
//  Created by Simone Paparo on 24/09/25.
//


// ExpensesForm.swift
import SwiftUI
import PhotosUI

struct ExpenseInput: Identifiable, Hashable {
    let id = UUID()
    var amount: Decimal
    var category: String
    var date: Date
    var note: String
    var projectName: String?   // or use a Project picker later
    var receiptImageData: Data?
}

struct ExpensesForm: View {
    // MARK: - Public API
    var initial: ExpenseInput? = nil
    var categories: [String] = ["Pasti", "Trasporti", "Alloggio", "Altro"]
    var onSubmit: (ExpenseInput) -> Void

    // MARK: - Local State
    @State private var projectName: String = ""
    @State private var amountText: String = ""
    @State private var selectedCategory: String = "Pasti"
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var receiptImageData: Data?

    // Validation
    @State private var amountError: String?

    var body: some View {
        Form {
            Section("Commessa (opzionale)") {
                TextField("Cliente/Commessa", text: $projectName)
                    .textInputAutocapitalization(.words)
            }

            Section("Dettagli spesa") {
                HStack {
                    Text("Importo (€)")
                    Spacer()
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: amountText) { _ in validateAmount() }
                        .frame(maxWidth: 160)
                }

                Picker("Categoria", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0) }
                }

                DatePicker("Data", selection: $date, displayedComponents: [.date])

                if let amountError {
                    Text(amountError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("Note & scontrino") {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...3)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    HStack {
                        Image(systemName: "doc.text.viewfinder")
                        Text(receiptImageData == nil ? "Aggiungi scontrino" : "Scontrino aggiunto")
                        Spacer()
                        if receiptImageData != nil {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadReceipt(from: newItem) }
                }

                if let data = receiptImageData, let uiImage = UIImage(data: data) {
                    // Small preview
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 4)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    Label("Salva spesa", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
            }
        }
        .onAppear(perform: prefill)
    }
}

// MARK: - Logic
private extension ExpensesForm {
    var isFormValid: Bool {
        parseDecimal(amountText) != nil && (amountError == nil)
    }

    func prefill() {
        guard let initial else { return }
        amountText = decimalString(initial.amount)
        selectedCategory = initial.category
        date = initial.date
        note = initial.note
        projectName = initial.projectName ?? ""
        receiptImageData = initial.receiptImageData
        validateAmount()
    }

    func validateAmount() {
        if let dec = parseDecimal(amountText), dec >= 0 {
            amountError = nil
        } else {
            amountError = "Inserisci un importo valido"
        }
    }

    func submit() {
        guard let dec = parseDecimal(amountText) else { return }
        let input = ExpenseInput(
            amount: dec,
            category: selectedCategory,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            projectName: projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : projectName,
            receiptImageData: receiptImageData
        )
        onSubmit(input)
    }

    func loadReceipt(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            receiptImageData = data
        }
    }
}

// MARK: - Decimal helpers (locale-aware)
private extension ExpensesForm {
    func parseDecimal(_ text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        // Try both decimal and currency styles
        if let n = formatter.number(from: text) {
            return n.decimalValue
        }
        formatter.numberStyle = .currency
        if let n = formatter.number(from: text) {
            return n.decimalValue
        }
        // Fallback: replace comma with dot
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    func decimalString(_ decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal)"
    }
}
