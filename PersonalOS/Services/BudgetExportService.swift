import Foundation

enum BudgetExportService {
    static func makeCSVFile(entries: [BudgetEntry], month: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = L.locale
        formatter.dateFormat = "yyyy-MM-dd"

        var rows = [
            ["Date", "Type", "Merchant", "Category", "Amount", "Currency", "Note", "Raw Input"]
        ]

        rows += entries
            .sorted { $0.date < $1.date }
            .map { entry in
                [
                    formatter.string(from: entry.date),
                    entry.isExpense ? "expense" : "income",
                    entry.merchant,
                    entry.budgetCategory.localizedName,
                    String(entry.amount),
                    entry.currency,
                    entry.note,
                    entry.rawInput ?? ""
                ]
            }

        let csv = rows
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n")

        let monthKey = month.formatted(.dateTime.year().month(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalOS-Budget-\(monthKey).csv")

        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
