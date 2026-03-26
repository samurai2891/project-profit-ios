import Foundation

/// 軽量な CSV プレビュー/取込用パーサ。
/// ledger import と settings import の共通下支えとして使う。
final class CSVImportService {

    static let shared = CSVImportService()

    func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            rows.append(parseCSVLine(line))
        }
        return rows
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
