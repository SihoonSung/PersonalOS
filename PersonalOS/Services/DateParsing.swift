import Foundation

struct ParsingDateContext: Sendable {
    let todayISO: String
    let weekday: String

    nonisolated static func current(date: Date = .now) -> ParsingDateContext {
        ParsingDateContext(
            todayISO: currentLocalISODateString(date: date),
            weekday: currentLocalWeekdayString(date: date)
        )
    }
}

private enum DateParsingCache {
    nonisolated static let localDateTimePattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?$/
    nonisolated static let iso8601 = LockedISO8601Parser()
}

private final class LockedISO8601Parser: @unchecked Sendable {
    private let lock = NSLock()
    private let fractionalFormatter: ISO8601DateFormatter
    private let internetFormatter: ISO8601DateFormatter

    init() {
        fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
    }

    func date(from string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractionalFormatter.date(from: string) ?? internetFormatter.date(from: string)
    }
}

nonisolated func currentLocalISODateString(date: Date = .now) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
        return date.formatted(.dateTime.year().month().day())
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
}

nonisolated func currentLocalWeekdayString(date: Date = .now) -> String {
    date.formatted(.dateTime.weekday(.wide).locale(L.locale))
}

nonisolated func parseISODate(_ isoString: String?) -> Date? {
    guard let str = isoString?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
        return nil
    }

    if let relative = relativeWordDate(str) {
        return relative
    }

    if let localDate = parseLocalDateOnly(str) {
        return localDate
    }

    if let date = DateParsingCache.iso8601.date(from: str) { return date }

    return parseLocalDateTime(str)
}

nonisolated private func relativeWordDate(_ string: String) -> Date? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)

    func atNoon(_ offset: Int) -> Date? {
        guard let day = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day)
    }

    switch string.lowercased() {
    case "today", "오늘": return atNoon(0)
    case "tomorrow", "내일": return atNoon(1)
    case "day after tomorrow", "the day after tomorrow", "모레": return atNoon(2)
    case "yesterday", "어제": return atNoon(-1)
    case "그저께", "그제": return atNoon(-2)
    default: return nil
    }
}

nonisolated private func parseLocalDateOnly(_ string: String) -> Date? {
    guard string.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
        return nil
    }

    let parts = string.split(separator: "-")
    guard
        parts.count == 3,
        let year = Int(parts[0]),
        let month = Int(parts[1]),
        let day = Int(parts[2])
    else { return nil }

    return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
}

nonisolated private func parseLocalDateTime(_ string: String) -> Date? {
    guard let match = string.firstMatch(of: DateParsingCache.localDateTimePattern),
          let year = Int(match.1),
          let month = Int(match.2),
          let day = Int(match.3),
          let hour = Int(match.4),
          let minute = Int(match.5),
          let second = Int(match.6)
    else { return nil }

    return Calendar.current.date(from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
    ))
}
