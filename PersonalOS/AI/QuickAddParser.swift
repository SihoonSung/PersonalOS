import Foundation

/// Parsed quick-add result: title + values keyed by property name.
struct ParsedEntry {
    var title: String = ""
    var texts: [String: String] = [:]     // text/select/url properties
    var numbers: [String: Double] = [:]
    var dates: [String: Date] = [:]
    var bools: [String: Bool] = [:]
}

/// Deterministic natural-language parser.
/// Primary path on devices without Apple Intelligence, and the fallback
/// when the on-device model fails. Handles Korean amounts (5천원, 3만원,
/// 1만5천원, 5,000원, $4.5) and relative dates via NaturalDateParser.
enum QuickAddParser {

    static func parse(_ input: String, database: POSDatabase, reference: Date = .now) -> ParsedEntry {
        var result = ParsedEntry()
        var remainder = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let properties = database.orderedProperties

        // --- Amount → first currency-formatted number property
        if let numberProp = properties.first(where: { $0.type == .number }),
           let (amount, matchedText) = extractAmount(from: remainder) {
            result.numbers[numberProp.name] = amount
            remainder = remainder.replacingOccurrences(of: matchedText, with: " ")
        }

        // --- Date → first date property
        if let dateProp = properties.first(where: { $0.type == .date }),
           let date = NaturalDateParser.parse(remainder, reference: reference) {
            result.dates[dateProp.name] = date
            remainder = removeDateWords(from: remainder)
        } else if let dateProp = properties.first(where: { $0.type == .date }),
                  database.templateKey == TemplateKey.budget {
            // Budget entries default to today
            result.dates[dateProp.name] = reference
        }

        // --- Select options mentioned verbatim
        for property in properties where property.type == .select {
            if let matched = property.config.selectOptions.first(where: { remainder.contains($0) }) {
                result.texts[property.name] = matched
                remainder = remainder.replacingOccurrences(of: matched, with: " ")
            }
        }

        // --- Budget heuristics: 수입/지출 분류
        if database.templateKey == TemplateKey.budget,
           let kindProp = properties.first(where: { $0.name == "유형" || $0.name == "분류" }),
           result.texts[kindProp.name] == nil {
            let incomeWords = ["월급", "급여", "입금", "받", "수입", "환급"]
            let isIncome = incomeWords.contains { input.contains($0) }
            let options = kindProp.config.selectOptions
            if let match = options.first(where: { isIncome ? $0.contains("수입") : $0.contains("지출") }) {
                result.texts[kindProp.name] = match
            }
        }

        // --- Title = what's left
        result.title = remainder
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.title.isEmpty {
            result.title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    // MARK: - Korean amount extraction

    /// Returns (amount, matched substring). Handles:
    /// "5000원", "5,000원", "5천원", "3만원", "1만5천원", "12만", "$4.50", "4500"
    static func extractAmount(from text: String) -> (Double, String)? {
        // $ amounts
        if let match = text.firstMatch(of: #/\$\s*([\d,]+(?:\.\d+)?)/#) {
            let numText = match.1.replacingOccurrences(of: ",", with: "")
            if let value = Double(numText) { return (value, String(match.0)) }
        }

        // 만/천 compound: 1만5천원, 3만원, 5천원, 12만
        if let match = text.firstMatch(of: #/([\d,.]+)?\s*만\s*([\d,.]+)?\s*천?\s*원?|([\d,.]+)\s*천\s*원?/#) {
            let full = String(match.0)
            // Only accept if it actually contains 만 or 천
            if full.contains("만") || full.contains("천") {
                var value: Double = 0
                if full.contains("만") {
                    let parts = full.components(separatedBy: "만")
                    let manPart = parts[0].replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    value += (Double(manPart) ?? 1) * 10_000
                    if parts.count > 1, parts[1].contains("천") {
                        let chonPart = parts[1].components(separatedBy: "천")[0]
                            .replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        value += (Double(chonPart) ?? 1) * 1_000
                    }
                } else if full.contains("천") {
                    let chonPart = full.components(separatedBy: "천")[0]
                        .replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    value = (Double(chonPart) ?? 1) * 1_000
                }
                if value > 0 { return (value, full) }
            }
        }

        // Plain number + 원 (or bare number ≥ 100 that looks like money)
        if let match = text.firstMatch(of: #/([\d,]+(?:\.\d+)?)\s*원/#) {
            let numText = match.1.replacingOccurrences(of: ",", with: "")
            if let value = Double(numText) { return (value, String(match.0)) }
        }
        // Swift regex doesn't support lookbehind — match start-of-string or a
        // non-date character before the number instead.
        if let match = text.firstMatch(of: #/(?:^|[^\d.,월일시분\/-])([\d,]{3,})(?![\d,]*[월일시분년\/-])/#) {
            let numText = match.1.replacingOccurrences(of: ",", with: "")
            if let value = Double(numText), value >= 100 { return (value, String(match.1)) }
        }
        return nil
    }

    private static func removeDateWords(from text: String) -> String {
        var result = text
        let dateWords = [
            "그저께", "그제", "어제", "오늘", "내일모레", "내일", "모레",
            "다음주", "다음 주", "저번주", "지난주", "지난 주", "이번주", "이번 주",
            "월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일",
            "yesterday", "today", "tomorrow",
        ]
        for word in dateWords {
            result = result.replacingOccurrences(of: word, with: " ")
        }
        result = result.replacingOccurrences(of: #"\d+\s*일\s*(뒤|후|전)"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\d{1,2}월\s*\d{1,2}일"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\d{4}-\d{1,2}-\d{1,2}"#, with: " ", options: .regularExpression)
        return result
    }
}
