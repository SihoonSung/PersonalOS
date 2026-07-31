import Foundation
import Combine
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI quick-add parsing (Apple FoundationModels), with the
/// deterministic QuickAddParser as fallback. All prompt lessons from the
/// previous app applied: today's date+weekday injected, model told to
/// output real calendar dates (never "yesterday"), and every date the
/// model returns is re-validated through NaturalDateParser.
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    @Published private(set) var isAvailable = false

    private init() {
        checkAvailability()
    }

    private func checkAvailability() {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: isAvailable = true
        default: isAvailable = false
        }
        #else
        isAvailable = false
        #endif
    }

    /// Parse natural language into a ParsedEntry for the given database.
    /// Always returns something usable — never blocks saving.
    func parse(_ input: String, database: POSDatabase) async -> ParsedEntry {
        let fallback = QuickAddParser.parse(input, database: database)

        #if canImport(FoundationModels)
        guard isAvailable else { return fallback }
        do {
            let prompt = buildPrompt(input: input, database: database)
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            if let parsed = decodeResponse(response.content, database: database, original: input) {
                return merge(ai: parsed, fallback: fallback)
            }
        } catch {
            // fall through to deterministic parser
        }
        #endif
        return fallback
    }

    // MARK: - Prompt

    private func buildPrompt(input: String, database: POSDatabase) -> String {
        var schemaLines: [String] = []
        for property in database.orderedProperties {
            var line = "- \"\(property.name)\": \(typeDescription(property))"
            if property.type == .select {
                line += " (옵션: \(property.config.selectOptions.joined(separator: ", ")))"
            }
            schemaLines.append(line)
        }

        return """
        사용자의 자연어 입력을 데이터베이스 항목으로 변환하세요. JSON만 출력하세요 (설명 금지).

        오늘은 \(NaturalDateParser.todayContext()) 입니다.
        날짜 규칙: '어제'는 오늘-1일, '내일'은 오늘+1일, '모레'는 오늘+2일. 요일 표현은 오늘 요일 기준으로 계산.
        절대 "yesterday", "어제" 같은 단어를 그대로 출력하지 말고, 반드시 계산된 실제 달력 날짜를 "yyyy-MM-dd" 형식으로 출력하세요.

        데이터베이스: "\(database.name)"
        속성:
        \(schemaLines.joined(separator: "\n"))

        출력 형식:
        {"title": "간결한 제목(상호명/할일명 등, 금액·날짜 표현 제외)", "values": {"속성이름": 값, ...}}
        - 숫자 속성: 숫자만 (예: 5000). "5천원"=5000, "3만원"=30000, "1만5천원"=15000
        - 날짜 속성: "yyyy-MM-dd" 문자열
        - 체크박스: true/false
        - 선택 속성: 반드시 위 옵션 중 하나
        - 입력에서 알 수 없는 속성은 생략

        입력: "\(input)"
        """
    }

    private func typeDescription(_ property: POSProperty) -> String {
        switch property.type {
        case .text: return "텍스트"
        case .number: return "숫자"
        case .date: return "날짜"
        case .checkbox: return "체크박스"
        case .select: return "선택"
        case .url: return "URL"
        }
    }

    // MARK: - Response decoding

    private func decodeResponse(_ raw: String, database: POSDatabase, original: String) -> ParsedEntry? {
        // Extract first JSON object from the response
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        let jsonText = String(raw[start...end])
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var result = ParsedEntry()
        result.title = (object["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if result.title.isEmpty {
            result.title = original
        }

        let values = object["values"] as? [String: Any] ?? [:]
        for property in database.orderedProperties {
            guard let rawValue = values[property.name] else { continue }
            switch property.type {
            case .text, .url:
                if let s = rawValue as? String, !s.isEmpty { result.texts[property.name] = s }
            case .select:
                if let s = rawValue as? String,
                   property.config.selectOptions.contains(s) {
                    result.texts[property.name] = s
                }
            case .number:
                if let n = numeric(rawValue) { result.numbers[property.name] = n }
            case .checkbox:
                if let b = rawValue as? Bool { result.bools[property.name] = b }
            case .date:
                // Safety net: whatever the model returned, run it through
                // the flexible parser (handles ISO and leaked relative words).
                if let s = rawValue as? String,
                   let d = NaturalDateParser.parseFlexible(s) {
                    result.dates[property.name] = d
                }
            }
        }
        return result
    }

    private func numeric(_ value: Any) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String {
            if let direct = Double(s.replacingOccurrences(of: ",", with: "")) { return direct }
            return QuickAddParser.extractAmount(from: s)?.0
        }
        return nil
    }

    /// AI result wins, but deterministic fallback fills gaps the model missed.
    private func merge(ai: ParsedEntry, fallback: ParsedEntry) -> ParsedEntry {
        var merged = ai
        for (k, v) in fallback.numbers where merged.numbers[k] == nil { merged.numbers[k] = v }
        for (k, v) in fallback.dates where merged.dates[k] == nil { merged.dates[k] = v }
        for (k, v) in fallback.texts where merged.texts[k] == nil { merged.texts[k] = v }
        for (k, v) in fallback.bools where merged.bools[k] == nil { merged.bools[k] = v }
        if merged.title.isEmpty { merged.title = fallback.title }
        return merged
    }
}
