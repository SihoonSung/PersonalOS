import Foundation

// MARK: - 성경 구절 시계
//
// 12시간제 시각을 장:절로 읽는다 — 07:21이면 "마태복음 7:21".
// 데이터는 Tools/build_verse_clock.py가 만든 verse-clock.json이고,
// 720칸(1:00~12:59)이 전부 채워져 있다.
//
// 25칸(4:55~4:59, 5:49~5:59, 10:53~10:59, 11:58~11:59)은 성경 어디에도
// 그 장:절이 없다 — 예를 들어 4장 55절을 가진 책이 한 권도 없다. 그 칸은
// 예비 구절로 채우고 `isExact = false`로 표시해 화면에서 구분한다.
//
// 이 파일과 verse-clock.json은 위젯 타깃 멤버십에도 추가해야 한다.

struct VerseClockEntry: Equatable {
    var bookName: String
    var chapter: Int
    var verse: Int
    var text: String
    /// 장:절이 실제로 지금 시각과 일치하는가.
    var isExact: Bool

    var reference: String { "\(bookName) \(chapter):\(verse)" }
}

enum VerseClock {

    private struct Payload: Decodable {
        struct Slot: Decodable {
            var book: String
            var bookKo: String
            var chapter: Int
            var verse: Int
            var text: String
            var textKo: String?
            var exact: Bool?
        }
        var language: String?
        var slots: [String: Slot]
    }

    private static let payload: Payload? = {
        // 앱 번들과 위젯 번들 모두에서 찾는다.
        let candidates = [Bundle.main] + Bundle.allBundles
        for bundle in candidates {
            guard let url = bundle.url(forResource: "verse-clock", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(Payload.self, from: data)
            else { continue }
            return decoded
        }
        return nil
    }()

    static var isAvailable: Bool { payload != nil }

    /// 한글 본문이 채워져 있으면 한글을, 아니면 공개도메인 영어를 쓴다.
    static var usesKorean: Bool { payload?.language == "ko" }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour24 = parts.hour ?? 0
        let minute = parts.minute ?? 0
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return String(format: "%02d:%02d", hour12, minute)
    }

    static func entry(for date: Date, calendar: Calendar = .current) -> VerseClockEntry? {
        guard let payload, let slot = payload.slots[key(for: date, calendar: calendar)] else { return nil }
        let korean = slot.textKo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (korean?.isEmpty == false ? korean! : slot.text)
        return VerseClockEntry(
            bookName: payload.language == "ko" ? slot.bookKo : displayName(for: slot),
            chapter: slot.chapter,
            verse: slot.verse,
            text: body,
            isExact: slot.exact ?? true
        )
    }

    /// 영어 본문일 땐 영어 책 이름이 자연스럽다.
    private static func displayName(for slot: Payload.Slot) -> String {
        englishNames[slot.book] ?? slot.bookKo
    }

    private static let englishNames: [String: String] = [
        "GENESIS": "Genesis", "EXODUS": "Exodus", "LEVITICUS": "Leviticus",
        "NUMBERS": "Numbers", "DEUTERONOMY": "Deuteronomy", "JOSHUA": "Joshua",
        "JUDGES": "Judges", "RUTH": "Ruth", "SAMUEL_1": "1 Samuel",
        "SAMUEL_2": "2 Samuel", "KINGS_1": "1 Kings", "KINGS_2": "2 Kings",
        "CHRONICLES_1": "1 Chronicles", "CHRONICLES_2": "2 Chronicles",
        "EZRA": "Ezra", "NEHEMIAH": "Nehemiah", "ESTHER": "Esther", "JOB": "Job",
        "PSALMS": "Psalm", "PROVERBS": "Proverbs", "ECCLESIASTES": "Ecclesiastes",
        "SONG_OF_SONGS": "Song of Songs", "ISAIAH": "Isaiah", "JEREMIAH": "Jeremiah",
        "LAMENTATIONS": "Lamentations", "EZEKIEL": "Ezekiel", "DANIEL": "Daniel",
        "HOSEA": "Hosea", "JOEL": "Joel", "AMOS": "Amos", "OBADIAH": "Obadiah",
        "JONAH": "Jonah", "MICAH": "Micah", "NAHUM": "Nahum", "HABAKKUK": "Habakkuk",
        "ZEPHANIAH": "Zephaniah", "HAGGAI": "Haggai", "ZECHARIAH": "Zechariah",
        "MALACHI": "Malachi", "MATTHEW": "Matthew", "MARK": "Mark", "LUKE": "Luke",
        "JOHN": "John", "ACTS": "Acts", "ROMANS": "Romans",
        "CORINTHIANS_1": "1 Corinthians", "CORINTHIANS_2": "2 Corinthians",
        "GALATIANS": "Galatians", "EPHESIANS": "Ephesians", "PHILIPPIANS": "Philippians",
        "COLOSSIANS": "Colossians", "THESSALONIANS_1": "1 Thessalonians",
        "THESSALONIANS_2": "2 Thessalonians", "TIMOTHY_1": "1 Timothy",
        "TIMOTHY_2": "2 Timothy", "TITUS": "Titus", "PHILEMON": "Philemon",
        "HEBREWS": "Hebrews", "JAMES": "James", "PETER_1": "1 Peter",
        "PETER_2": "2 Peter", "JOHN_1": "1 John", "JOHN_2": "2 John",
        "JOHN_3": "3 John", "JUDE": "Jude", "REVELATION": "Revelation",
    ]
}
