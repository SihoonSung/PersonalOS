import Foundation

/// Deterministic Korean/English date parsing.
/// Used as the AI-off fallback AND as a safety net when the model
/// leaks relative words ("어제", "yesterday") instead of real dates.
/// All results are anchored to 12:00 local time to avoid timezone
/// off-by-one at day boundaries (lesson from the previous app).
enum NaturalDateParser {

    static func parse(_ raw: String, reference: Date = .now) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        let cal = Calendar.current

        // 1. Plain relative words
        let relativeDays: [String: Int] = [
            "그저께": -2, "그제": -2, "어제": -1, "오늘": 0, "내일": 1, "모레": 2, "내일모레": 2,
            "yesterday": -1, "today": 0, "tomorrow": 1,
        ]
        for (word, offset) in relativeDays where text.contains(word) {
            return noon(cal.date(byAdding: .day, value: offset, to: reference) ?? reference)
        }

        // 2. Weekday expressions: 이번주/다음주/저번주 + 요일
        if let date = parseWeekday(text, reference: reference) {
            return date
        }

        // 3. "N일 뒤/후/전"
        if let match = text.firstMatch(of: #/(\d+)\s*일\s*(뒤|후|전)/#) {
            let n = Int(match.1) ?? 0
            let offset = match.2 == "전" ? -n : n
            return noon(cal.date(byAdding: .day, value: offset, to: reference) ?? reference)
        }

        // 4. Explicit dates: yyyy-MM-dd / M월 d일 / M/d
        if let match = text.firstMatch(of: #/(\d{4})-(\d{1,2})-(\d{1,2})/#) {
            return makeDate(year: Int(match.1), month: Int(match.2), day: Int(match.3))
        }
        if let match = text.firstMatch(of: #/(\d{1,2})월\s*(\d{1,2})일/#) {
            return makeDate(year: nil, month: Int(match.1), day: Int(match.2), reference: reference)
        }
        if let match = text.firstMatch(of: #/(\d{1,2})\/(\d{1,2})/#) {
            return makeDate(year: nil, month: Int(match.1), day: Int(match.2), reference: reference)
        }

        return nil
    }

    /// ISO string first, then natural language — for cleaning up AI output.
    static func parseFlexible(_ raw: String, reference: Date = .now) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let isoWithTime = ISO8601DateFormatter()
        if let d = isoWithTime.parse(text) { return d }

        // yyyy-MM-dd without time → local noon
        if let match = text.firstMatch(of: #/^(\d{4})-(\d{2})-(\d{2})$/#) {
            return makeDate(year: Int(match.1), month: Int(match.2), day: Int(match.3))
        }
        // yyyy-MM-ddTHH:mm(:ss) without timezone → local
        if let match = text.firstMatch(of: #/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/#) {
            var comps = DateComponents()
            comps.year = Int(match.1); comps.month = Int(match.2); comps.day = Int(match.3)
            comps.hour = Int(match.4); comps.minute = Int(match.5)
            return Calendar.current.date(from: comps)
        }

        return parse(text, reference: reference)
    }

    // MARK: - Helpers

    private static func parseWeekday(_ text: String, reference: Date) -> Date? {
        let weekdays: [(String, Int)] = [
            ("일요일", 1), ("월요일", 2), ("화요일", 3), ("수요일", 4),
            ("목요일", 5), ("금요일", 6), ("토요일", 7),
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7),
        ]
        guard let (_, target) = weekdays.first(where: { text.contains($0.0) }) else { return nil }

        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: reference)

        var weekOffset = 0
        if text.contains("다음주") || text.contains("다음 주") || text.contains("next week") {
            weekOffset = 1
        } else if text.contains("저번주") || text.contains("지난주") || text.contains("지난 주") || text.contains("last week") {
            weekOffset = -1
        }

        var dayDiff = target - todayWeekday
        if weekOffset == 0 {
            // "이번주 금요일" or bare "금요일": upcoming occurrence (today counts)
            if dayDiff < 0 { dayDiff += 7 }
        } else {
            // Anchor to that week's same weekday
            dayDiff += weekOffset * 7
        }
        let date = cal.date(byAdding: .day, value: dayDiff, to: reference) ?? reference
        return noon(date)
    }

    private static func noon(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private static func makeDate(year: Int?, month: Int?, day: Int?, reference: Date = .now) -> Date? {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year ?? Calendar.current.component(.year, from: reference)
        comps.month = month
        comps.day = day
        comps.hour = 12
        return Calendar.current.date(from: comps)
    }

    static func todayContext(reference: Date = .now) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy-MM-dd (EEEE)"
        return df.string(from: reference)
    }
}

private extension ISO8601DateFormatter {
    func parse(_ text: String) -> Date? { date(from: text) }
}
