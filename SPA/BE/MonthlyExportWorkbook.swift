import Foundation
import ZIPFoundation

struct MonthlyExportWorkbook {
    struct Result {
        let fileURL: URL
        let sessionCount: Int
        let expenseCount: Int
    }

    enum WorkbookError: LocalizedError {
        case templateMissing
        case templateCorrupted
        case writeFailed(Error)
        case archiveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .templateMissing:
                return "Impossibile trovare il modello di export."
            case .templateCorrupted:
                return "Il modello di export è danneggiato."
            case .writeFailed(let error):
                return "Impossibile aggiornare il modello: \(error.localizedDescription)"
            case .archiveFailed(let error):
                return "Impossibile creare il file Excel: \(error.localizedDescription)"
            }
        }
    }

    private static let templateName = "MonthlyExportTemplate"
    private static let templateExtension = "xlsx"

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func makeWorkbook(title: String, sessions: [WorkSession], expenses: [Expense]) throws -> Result {
        guard let templateURL = Self.locateTemplate() else {
            throw WorkbookError.templateMissing
        }

        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory.appendingPathComponent("MonthlyExport-\(UUID().uuidString)", isDirectory: true)
        let extractionDirectory = workingDirectory.appendingPathComponent("unpacked", isDirectory: true)

        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)

        do {
            try Self.extractArchive(at: templateURL, to: extractionDirectory)
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw WorkbookError.templateCorrupted
        }

        do {
            try Self.writeSessionsSheet(title: title, sessions: sessions, at: extractionDirectory.appendingPathComponent("xl/worksheets/sheet1.xml"))
            try Self.writeExpensesSheet(expenses: expenses, at: extractionDirectory.appendingPathComponent("xl/worksheets/sheet2.xml"))
            try Self.writeCoreProperties(title: title, at: extractionDirectory.appendingPathComponent("docProps/core.xml"))
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw WorkbookError.writeFailed(error)
        }

        let sanitizedTitle = Self.sanitizedFileName(from: title)
        let fileName = "Report-\(sanitizedTitle)-\(Self.fileNameFormatter.string(from: Date())).xlsx"
        let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try Self.createArchive(from: extractionDirectory, destination: destinationURL)
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw WorkbookError.archiveFailed(error)
        }

        try? fileManager.removeItem(at: workingDirectory)
        return Result(fileURL: destinationURL, sessionCount: sessions.count, expenseCount: expenses.count)
    }
}

// MARK: - Template helpers
private extension MonthlyExportWorkbook {
    static func locateTemplate() -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: templateName, withExtension: templateExtension)
        #else
        if let url = Bundle.main.url(forResource: templateName, withExtension: templateExtension) {
            return url
        }
        return Bundle(for: BundleMarker.self).url(forResource: templateName, withExtension: templateExtension)
        #endif
    }

    static func extractArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let fileManager = FileManager.default
        for entry in archive {
            let outputURL = destinationURL.appendingPathComponent(entry.path)
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: outputURL)
        }
    }

    static func createArchive(from folderURL: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let archive = try Archive(url: destination, accessMode: .create)
        guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw WorkbookError.archiveFailed(WorkbookError.templateCorrupted)
        }
        let basePath = folderURL.path + "/"
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                continue
            }
            let path = String(fileURL.path.dropFirst(basePath.count))
            try archive.addEntry(with: path, fileURL: fileURL, compressionMethod: CompressionMethod.deflate)
        }
    }

    static func sanitizedFileName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutDiacritics = trimmed.folding(options: .diacriticInsensitive, locale: .current)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = withoutDiacritics.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var sanitized = String(mapped)
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if sanitized.isEmpty {
            sanitized = "Mese"
        }
        return sanitized
    }
}

private final class BundleMarker {}

// MARK: - Sheet writers
private extension MonthlyExportWorkbook {
    static func writeSessionsSheet(title: String, sessions: [WorkSession], at url: URL) throws {
        var rows: [[String]] = []
        rows.append(["Data", "Inizio", "Fine", "Pausa time", "Tipo", "Commessa"])

        for session in sessions {
            let dateString = dateFormatter.string(from: session.start)
            let startString = timeFormatter.string(from: session.start)
            let projectName = session.project?.name ?? "Senza commessa"
            var endString = "—"
            let breakTimeString = formatDuration(minutes: session.breakMinutes)
            let tipo = session.sessionType
            
            if let end = session.end {
                endString = timeFormatter.string(from: end)
            }
            
            rows.append([dateString, startString, endString, breakTimeString, tipo, projectName])
        }

        let xml = worksheetXML(rows: rows)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeExpensesSheet(expenses: [Expense], at url: URL) throws {
        var rows: [[String]] = []
        rows.append(["Data", "Importo", "Categoria", "Commessa", "Note"])

        var totalAmount = Decimal.zero
        for expense in expenses {
            totalAmount += expense.amount
            let dateString = dateFormatter.string(from: expense.date)
            let amountString = currencyString(expense.amount)
            let projectName = expense.project?.name ?? "Senza commessa"
            let note = expense.note ?? ""
            rows.append([dateString, amountString, expense.category, projectName, note])
        }

        if !expenses.isEmpty {
            rows.append(Array(repeating: "", count: 5))
            rows.append(["Totale spese", currencyString(totalAmount), "", "", ""])
        }

        let xml = worksheetXML(rows: rows)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeCoreProperties(title: String, at url: URL) throws {
        let now = isoFormatter.string(from: Date())
        let escapedTitle = xmlEscaped(title)
        let xml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>\(escapedTitle)</dc:title>
  <dc:creator>SPA</dc:creator>
  <cp:lastModifiedBy>SPA</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
</cp:coreProperties>
"""
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - XML helpers
private extension MonthlyExportWorkbook {
    static func worksheetXML(rows: [[String]]) -> String {
        guard let columnCount = rows.first?.count else {
            return "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>"
        }
        let totalRows = rows.count
        let lastColumn = columnLetter(for: columnCount)
        let dimensionRef = "A1:\(lastColumn)\(max(totalRows, 1))"
        let rowsXML = rows.enumerated().map { index, values in
            rowXML(index: index + 1, values: values)
        }.joined(separator: "\n")

        return """
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetPr><outlinePr summaryBelow="1" summaryRight="1" /><pageSetUpPr /></sheetPr><dimension ref="\(dimensionRef)" /><sheetViews><sheetView workbookViewId="0"><selection activeCell="A1" sqref="A1" /></sheetView></sheetViews><sheetFormatPr baseColWidth="8" defaultRowHeight="15" /><sheetData>
\(rowsXML)
</sheetData><pageMargins left="0.75" right="0.75" top="1" bottom="1" header="0.5" footer="0.5" /></worksheet>
"""
    }

    static func rowXML(index: Int, values: [String]) -> String {
        let cellXML = values.enumerated().map { columnIndex, value -> String in
            let column = columnLetter(for: columnIndex + 1)
            let reference = "\(column)\(index)"
            let escaped = xmlEscaped(value)
            return "    <c r=\"\(reference)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>"
        }.joined(separator: "\n")
        return """
  <row r="\(index)">
\(cellXML)
  </row>
"""
    }

    static func columnLetter(for index: Int) -> String {
        var value = index
        var result = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            if let scalar = UnicodeScalar(65 + remainder) {
                result = String(scalar) + result
            }
            value = (value - 1) / 26
        }
        return result
    }

    static func xmlEscaped(_ value: String) -> String {
        var string = value.replacingOccurrences(of: "&", with: "&amp;")
        string = string.replacingOccurrences(of: "<", with: "&lt;")
        string = string.replacingOccurrences(of: ">", with: "&gt;")
        string = string.replacingOccurrences(of: "\"", with: "&quot;")
        string = string.replacingOccurrences(of: "'", with: "&apos;")
        return string
    }

    static func formatDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    static func currencyString(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return currencyFormatter.string(from: number) ?? "\(value)"
    }

    static func payableMinutes(start: Date, end: Date, breakMin: Int, rule: RoundingRule) -> Int {
        let s = rounded(start, rule: rule)
        let e = rounded(end, rule: rule)
        return max(0, Int(e.timeIntervalSince(s)/60) - max(0, breakMin))
    }

    private static func rounded(_ date: Date, rule: RoundingRule) -> Date {
        switch rule {
        case .off: return date
        case .nearest5:  return date.rounded(to: 5*60)
        case .nearest15: return date.rounded(to: 15*60)
        case .nearest30: return date.rounded(to: 30*60)
        }
    }
}

private extension Date {
    func rounded(to step: TimeInterval) -> Date {
        let t = timeIntervalSince1970
        let r = (t / step).rounded() * step
        return Date(timeIntervalSince1970: r)
    }
}
