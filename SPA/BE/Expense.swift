import Foundation
import SwiftData

@Model
final class Expense {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Decimal = .zero
    var category: String = ""
    var note: String?
    var receiptImageData: Data?

    @Relationship(inverse: \Project.expenses)
    var project: Project?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(amount: Decimal, category: String, date: Date, note: String?, project: Project?, receiptImageData: Data?) {
        self.amount = amount
        self.category = category
        self.date = date
        self.note = note
        self.project = project
        self.receiptImageData = receiptImageData
    }
}
