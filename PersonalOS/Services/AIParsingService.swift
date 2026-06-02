import Foundation
import FoundationModels

// MARK: - Generable Output Types

@Generable
struct ParsedTodoInput {
    @Guide(description: "작업 제목. 간결하게, 입력언어 유지")
    var title: String

    @Guide(description: "마감 날짜/시간 ISO 8601 형식 (예: 2025-07-15T15:00:00). 언급 없으면 null")
    var dueDateISO: String?

    @Guide(description: "우선순위. 0=없음, 1=낮음, 2=보통, 3=높음. '급하게','중요' 등 키워드로 추론")
    var priority: Int

    @Guide(description: "반복 규칙 RRULE 형식 (예: FREQ=DAILY, FREQ=WEEKLY;BYDAY=MO). 반복 언급 없으면 null")
    var repeatRule: String?

    @Guide(description: "제목 외 추가 메모. 없으면 null")
    var notes: String?
}

@Generable
struct ParsedBudgetInput {
    @Guide(description: "상호명 또는 결제처 이름. 입력에서 추출하거나 추론")
    var merchant: String

    @Guide(description: "금액. 숫자만, 통화 기호 없음. '만원'=10000, '달러'=USD 금액")
    var amount: Double

    @Guide(description: "'expense'(지출) 또는 'income'(수입). '월급','급여','수입' 등은 income")
    var type: String

    @Guide(description: "카테고리. 반드시 다음 중 하나: 식비, 카페, 교통, 쇼핑, 여가, 의료/건강, 구독, 공과금, 급여, 투자수입, 기타. 상호명으로 추론 (스타벅스→카페, 버스/지하철→교통, 넷플릭스→구독, GS25/CU→식비)")
    var category: String

    @Guide(description: "거래 날짜 ISO 8601 형식. '어제'='yesterday', '오늘'='today'. 미지정시 오늘 날짜")
    var dateISO: String

    @Guide(description: "추가 메모. 없으면 null")
    var note: String?
}

// MARK: - AI Availability

@Observable
final class AIAvailabilityManager {
    private(set) var isAvailable: Bool = false
    private(set) var unavailableReason: String = ""

    init() {
        checkAvailability()
    }

    private func checkAvailability() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            isAvailable = true
        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .deviceNotEligible:
                unavailableReason = "이 기기는 Apple Intelligence를 지원하지 않습니다."
            case .appleIntelligenceNotEnabled:
                unavailableReason = "Apple Intelligence가 꺼져 있습니다. 설정에서 켜주세요."
            case .modelNotReady:
                unavailableReason = "AI 모델을 다운로드하는 중입니다. 잠시 후 다시 시도해주세요."
            @unknown default:
                unavailableReason = "AI 기능을 사용할 수 없습니다."
            }
        @unknown default:
            isAvailable = false
        }
    }
}

// MARK: - Parsing Service

actor AIParsingService {
    // 파싱은 매번 새 LanguageModelSession — 4096 토큰 컨텍스트 누적 방지
    func parseTodo(input: String) async throws -> ParsedTodoInput {
        let todayStr = Date.now.formatted(.dateTime.year().month().day())
        let session = LanguageModelSession(instructions: """
            오늘 날짜: \(todayStr)
            작업 파싱 전문가입니다. 한국어/영어 자연어에서 할 일 정보를 추출합니다.
            날짜 표현: '내일'=tomorrow, '모레'=day after tomorrow, '이번주 금요일'=this Friday, '다음주 월요일'=next Monday.
            시간 미지정시 오후 11:59:00으로 설정합니다.
            """)
        let response = try await session.respond(to: input, generating: ParsedTodoInput.self)
        return response.content
    }

    func parseBudget(input: String) async throws -> ParsedBudgetInput {
        let todayStr = Date.now.formatted(Date.ISO8601FormatStyle().year().month().day())
        let session = LanguageModelSession(instructions: """
            오늘 날짜: \(todayStr)
            가계부 파싱 전문가입니다. 한국어/영어에서 거래 정보를 추출합니다.
            금액 단위: '원'=KRW, '달러'/'$'=USD 금액 그대로, '만원'=×10000, '천원'=×1000.
            날짜: '어제'=yesterday ISO, '오늘'=today ISO, 미지정=오늘.
            """)
        let response = try await session.respond(to: input, generating: ParsedBudgetInput.self)
        return response.content
    }

    func generateBudgetSummary(
        month: String,
        income: Double,
        expense: Double,
        categorySummary: String,
        delta: Double
    ) async throws -> String {
        let session = LanguageModelSession(
            instructions: "개인 재무 비서입니다. 데이터를 바탕으로 친근한 한국어 2~3문장으로 소비 패턴을 요약합니다. 제공된 수치만 사용하고 직접 계산하지 않습니다."
        )
        let prompt = """
            \(month) 가계부:
            총 수입: \(income.formatted())원
            총 지출: \(expense.formatted())원
            카테고리별: \(categorySummary)
            지난달 대비: \(delta > 0 ? "+" : "")\(delta.formatted())원

            2~3문장으로 소비 패턴을 요약해주세요.
            """
        let response = try await session.respond(to: prompt)
        return response.content
    }
}

// MARK: - Helpers

func withAIFallback<T>(fallback: T, operation: () async throws -> T) async -> T {
    do {
        return try await operation()
    } catch {
        return fallback
    }
}

// MARK: - Date Parsing Helper

func parseISODate(_ isoString: String?) -> Date? {
    guard let str = isoString, !str.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: str) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: str) { return date }
    // 날짜만 있는 경우
    formatter.formatOptions = [.withFullDate]
    return formatter.date(from: str)
}
