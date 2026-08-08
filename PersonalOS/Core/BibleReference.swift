import Foundation

// MARK: - 성경 구절 참조
//
// 설교 본문을 자유 텍스트로 두면 "요 3:16", "요한복음 3장 16절", "John 3:16"이
// 뒤섞여 나중에 정렬도 검색도 안 된다. 입력은 아무렇게나 받되 **저장은 한
// 형식으로** 정규화한다.
//
// 말씀 시계(verse-clock.json)에도 한글 책 이름이 있지만 57권뿐이라
// (시각과 맞는 장:절이 있는 책만) 여기서 66권 정경을 따로 정의한다.

struct BibleBook: Identifiable, Hashable, Sendable {
    /// 정경 순서 1…66. 정렬 키로 쓴다.
    let order: Int
    let name: String
    let abbreviation: String

    var id: Int { order }
    var isOldTestament: Bool { order <= 39 }
    var testamentName: String { isOldTestament ? "구약" : "신약" }
}

struct BibleReference: Equatable, Sendable {
    let book: BibleBook
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?

    /// 저장·표시용 정규 형식 — "요한복음 3:16-18".
    var display: String {
        var text = "\(book.name) \(chapter)"
        if let verseStart {
            text += ":\(verseStart)"
            if let verseEnd, verseEnd != verseStart { text += "-\(verseEnd)" }
        }
        return text
    }

    /// 정렬용 — 권·장·절 순.
    var sortKey: Int { book.order * 1_000_000 + chapter * 1_000 + (verseStart ?? 0) }
}

enum BibleCanon {

    static let books: [BibleBook] = {
        let raw: [(String, String)] = [
            ("창세기","창"), ("출애굽기","출"), ("레위기","레"), ("민수기","민"), ("신명기","신"),
            ("여호수아","수"), ("사사기","삿"), ("룻기","룻"), ("사무엘상","삼상"), ("사무엘하","삼하"),
            ("열왕기상","왕상"), ("열왕기하","왕하"), ("역대상","대상"), ("역대하","대하"),
            ("에스라","스"), ("느헤미야","느"), ("에스더","에"), ("욥기","욥"), ("시편","시"),
            ("잠언","잠"), ("전도서","전"), ("아가","아"), ("이사야","사"), ("예레미야","렘"),
            ("예레미야애가","애"), ("에스겔","겔"), ("다니엘","단"), ("호세아","호"), ("요엘","욜"),
            ("아모스","암"), ("오바댜","옵"), ("요나","욘"), ("미가","미"), ("나훔","나"),
            ("하박국","합"), ("스바냐","습"), ("학개","학"), ("스가랴","슥"), ("말라기","말"),
            ("마태복음","마"), ("마가복음","막"), ("누가복음","눅"), ("요한복음","요"),
            ("사도행전","행"), ("로마서","롬"), ("고린도전서","고전"), ("고린도후서","고후"),
            ("갈라디아서","갈"), ("에베소서","엡"), ("빌립보서","빌"), ("골로새서","골"),
            ("데살로니가전서","살전"), ("데살로니가후서","살후"), ("디모데전서","딤전"),
            ("디모데후서","딤후"), ("디도서","딛"), ("빌레몬서","몬"), ("히브리서","히"),
            ("야고보서","약"), ("베드로전서","벧전"), ("베드로후서","벧후"), ("요한1서","요일"),
            ("요한2서","요이"), ("요한3서","요삼"), ("유다서","유"), ("요한계시록","계"),
        ]
        return raw.enumerated().map { BibleBook(order: $0.offset + 1, name: $0.element.0, abbreviation: $0.element.1) }
    }()

    /// 이름·약어 → 책. 공백은 무시한다.
    private static let index: [String: BibleBook] = {
        var map: [String: BibleBook] = [:]
        for book in books {
            map[book.name] = book
            map[book.abbreviation] = book
        }
        // 흔한 변형 몇 개만 손으로 — 자동 생성하면 약어끼리 충돌한다.
        let aliases: [String: String] = [
            "시": "시편", "시편서": "시편", "아가서": "아가", "애가": "예레미야애가",
            "계시록": "요한계시록", "요한계시": "요한계시록",
            "요1서": "요한1서", "요2서": "요한2서", "요3서": "요한3서",
            "고린도전": "고린도전서", "고린도후": "고린도후서",
        ]
        for (alias, target) in aliases {
            if let book = books.first(where: { $0.name == target }) { map[alias] = book }
        }
        return map
    }()

    static func book(named raw: String) -> BibleBook? {
        let key = raw.replacingOccurrences(of: " ", with: "")
        return index[key]
    }

    static func search(_ query: String) -> [BibleBook] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return books }
        return books.filter { $0.name.contains(q) || $0.abbreviation.contains(q) }
    }

    /// "요 3:16", "요한복음 3장 16절", "시편 23", "롬 8:28-30" 전부 받는다.
    /// 책 이름을 못 찾으면 nil — 자유 텍스트로 남겨 두는 편이 낫다.
    static func parse(_ raw: String) -> BibleReference? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 앞에서부터 가장 긴 책 이름을 찾는다 ("요한복음"이 "요"보다 먼저 잡히게).
        let compact = text.replacingOccurrences(of: " ", with: "")
        var matched: BibleBook?
        var remainder = ""
        for length in stride(from: min(compact.count, 8), through: 1, by: -1) {
            let candidate = String(compact.prefix(length))
            if let book = index[candidate] {
                matched = book
                remainder = String(compact.dropFirst(length))
                break
            }
        }
        guard let book = matched else { return nil }

        // 남은 부분에서 숫자만 순서대로 뽑는다: 장, 절, 끝절.
        var numbers: [Int] = []
        var current = ""
        for ch in remainder {
            if ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                numbers.append(Int(current) ?? 0)
                current = ""
            }
        }
        if !current.isEmpty { numbers.append(Int(current) ?? 0) }

        guard let chapter = numbers.first, chapter > 0 else { return nil }
        let start = numbers.count > 1 ? numbers[1] : nil
        let end = numbers.count > 2 ? numbers[2] : nil
        return BibleReference(book: book, chapter: chapter, verseStart: start, verseEnd: end)
    }

    /// 입력을 정규 형식으로. 해석 못 하면 원문 그대로 돌려준다.
    static func normalize(_ raw: String) -> String {
        parse(raw)?.display ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
