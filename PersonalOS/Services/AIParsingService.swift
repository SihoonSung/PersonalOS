import Foundation
import FoundationModels

// MARK: - Generable Output Types

@Generable
struct ParsedInputClassification {
    @Guide(description: """
        Input kind. Return exactly one of:
        - todo: a task, reminder, appointment, chore, or something the user needs to do later.
        - budget: an expense, income, purchase, payment, salary, or financial transaction the user wants to record.
        If the text mentions money but is asking the user to do something later, choose todo.
        """)
    var type: String
}

@Generable
struct ParsedTodoInput {
    @Guide(description: "작업 제목. 간결하게, 입력언어 유지")
    var title: String

    @Guide(description: "마감 날짜와 시간. 반드시 'yyyy-MM-ddTHH:mm:ss' 형식의 실제 달력 값으로 출력 (예: 2026-06-03T15:00:00). '내일','금요일' 같은 단어를 그대로 쓰지 말고 오늘 기준 실제 날짜로 계산할 것. 언급 없으면 null")
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

    @Guide(description: "숫자 금액만. 단위 변환 규칙: '만원'→×10000 (예: 3만원=30000), '천원'→×1000 (예: 3천원=3000). '달러'/'$'는 변환 없이 그대로 (예: 5달러=5.0, $99=99.0, 3.5달러=3.5). 절대로 달러에 100을 곱하지 말 것.")
    var amount: Double

    @Guide(description: "'expense'(지출) 또는 'income'(수입). '월급','급여','수입' 등은 income")
    var type: String

    @Guide(description: "카테고리 raw key. 반드시 다음 중 하나: food, coffee, transport, shopping, entertainment, health, subscription, utility, salary, investmentIncome, other. 상호명으로 추론 (스타벅스→coffee, 버스/지하철→transport, 넷플릭스→subscription, GS25/CU→food)")
    var category: String

    @Guide(description: "거래 날짜. 반드시 'yyyy-MM-dd' 형식의 실제 달력 값으로 출력 (예: 2026-06-01). '어제','오늘' 같은 단어를 그대로 쓰지 말고 오늘 기준 실제 날짜로 계산할 것. 미지정 시 오늘 날짜.")
    var dateISO: String

    @Guide(description: "통화 코드. '달러','$','USD' 언급 시 'USD', '원','₩','KRW' 언급 시 'KRW', 미지정 시 기본 통화")
    var currency: String

    @Guide(description: "추가 메모. 없으면 null")
    var note: String?
}

// MARK: - Calendar Classification

@Generable
struct CalendarClassification {
    @Guide(description: """
        The most suitable calendar name from the provided list.
        Classify based on task title:
        - Medical/health keywords (hospital, doctor, dentist, pharmacy, 병원, 치과, 약) → prefer health/personal calendar
        - Work/meeting keywords (meeting, report, deadline, 회의, 보고서, 미팅, 업무) → prefer work calendar
        - Exercise/fitness keywords (gym, run, workout, 운동, 헬스, 러닝) → prefer health/personal calendar
        - Study/learning keywords (study, exam, class, 공부, 시험, 수업) → prefer school/personal calendar
        - Family/personal keywords (family, 가족, 생일, birthday) → prefer personal/home calendar
        If no clearly matching calendar, return the default calendar name provided.
        Return EXACTLY one of the calendar names from the provided list — no modifications.
        """)
    var calendarName: String
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
                unavailableReason = L.aiReasonDeviceNotEligible
            case .appleIntelligenceNotEnabled:
                unavailableReason = L.aiReasonNotEnabled
            case .modelNotReady:
                unavailableReason = L.aiReasonModelNotReady
            @unknown default:
                unavailableReason = L.aiReasonUnavailable
            }
        @unknown default:
            isAvailable = false
            unavailableReason = L.aiReasonUnavailable
        }
    }
}

// MARK: - Parsing Service

actor AIParsingService {
    // 파싱은 매번 새 LanguageModelSession — 4096 토큰 컨텍스트 누적 방지
    func classifyInput(input: String) async throws -> ParsedInputClassification {
        let session = LanguageModelSession(instructions: """
            You classify PersonalOS quick-add input.
            Return exactly one type:
            - todo: a task/reminder/action the user still needs to do
            - budget: a completed or explicit income/expense/transaction record

            Important:
            - "내일 엄마한테 3만원 보내기" / "send mom $30 tomorrow" is todo.
            - "엄마한테 3만원 보냄" / "sent mom $30" is budget.
            - Salary, allowance, purchase, restaurant, coffee, transport, subscription, and receipt-like entries are budget.
            - Meetings, appointments, deadlines, calls, and errands are todo.
            """)
        let response = try await session.respond(to: input, generating: ParsedInputClassification.self)
        return response.content
    }

    func parseTodo(
        input: String,
        dateContext: ParsingDateContext = .current()
    ) async throws -> ParsedTodoInput {
        let todayStr = dateContext.todayISO
        let weekdayStr = dateContext.weekday
        let session = LanguageModelSession(instructions: """
            오늘은 \(todayStr) (\(weekdayStr))입니다.
            작업 파싱 전문가입니다. 한국어/영어 자연어에서 할 일 정보를 추출합니다.

            날짜 계산 규칙 (반드시 준수):
            - 모든 상대 표현은 오늘(\(todayStr)) 기준으로 실제 달력 날짜를 계산해 출력합니다.
            - 오늘=\(todayStr), 내일=오늘+1일, 모레=오늘+2일, 어제=오늘-1일.
            - '이번주 금요일','다음주 월요일' 등은 오늘 요일(\(weekdayStr))을 기준으로 실제 날짜를 계산합니다.
            - dueDateISO는 'yyyy-MM-ddTHH:mm:ss' 형식으로만 출력하고, '내일'·요일 같은 단어를 그대로 넣지 않습니다.
            - 시간이 명시되지 않으면 23:59:00으로 설정합니다.
            """)
        let response = try await session.respond(to: input, generating: ParsedTodoInput.self)
        return response.content
    }

    func parseBudget(
        input: String,
        defaultCurrency: String = "KRW",
        dateContext: ParsingDateContext = .current()
    ) async throws -> ParsedBudgetInput {
        let todayStr = dateContext.todayISO
        let weekdayStr = dateContext.weekday
        let currencyNote = defaultCurrency == "USD"
            ? "기본 통화는 USD입니다. 통화 미지정 시 USD로 간주합니다."
            : "기본 통화는 KRW(원)입니다. 통화 미지정 시 KRW로 간주합니다."
        let session = LanguageModelSession(instructions: """
            오늘은 \(todayStr) (\(weekdayStr))입니다.
            가계부 파싱 전문가입니다. 한국어/영어에서 거래 정보를 추출합니다.
            \(currencyNote)

            금액 변환 규칙 (반드시 준수):
            - '만원' → ×10000 (예: 3만원=30000, 1만5천원=15000)
            - '천원' → ×1000 (예: 3천원=3000)
            - '달러', '$', 'dollar' → 변환 없이 숫자 그대로 (예: 5달러=5.0, $99=99.0, 3.5달러=3.5)
            - '센트', 'cent' → ÷100 (예: 50센트=0.5)
            - '원', 'KRW' → 변환 없이 숫자 그대로 (예: 6000원=6000)
            - 달러에 100을 곱하는 것은 절대 금지

            날짜 계산 규칙 (반드시 준수):
            - 모든 상대 표현은 오늘(\(todayStr)) 기준으로 실제 달력 날짜를 계산해 출력합니다.
            - '오늘' 또는 미지정 → \(todayStr), '어제' → 하루 전, '그저께' → 이틀 전.
            - 요일·날짜 언급 시 오늘 요일(\(weekdayStr))을 기준으로 실제 날짜로 변환합니다.
            - dateISO는 'yyyy-MM-dd' 형식으로만 출력하고, '어제'·요일 같은 단어를 그대로 넣지 않습니다.
            """)
        let response = try await session.respond(to: input, generating: ParsedBudgetInput.self)
        return response.content
    }

    // Agent 패턴: 잘못된 이름 반환 시 피드백 제공 후 재시도 (최대 3회)
    func classifyCalendar(
        todoTitle: String,
        availableCalendars: [String],
        defaultCalendar: String
    ) async throws -> String {
        guard !availableCalendars.isEmpty else { return defaultCalendar }

        let calendarList = availableCalendars.joined(separator: "\n- ")
        // 세션을 재사용해서 대화 컨텍스트 유지 — 잘못된 답 → 피드백 → 재시도
        let session = LanguageModelSession(instructions: """
            You are a calendar classifier agent.
            Your ONLY job: return exactly one calendar name from this list:
            - \(calendarList)

            Rules:
            1. Return ONLY the calendar name — nothing else, no punctuation added
            2. The name must match EXACTLY (case-sensitive) one from the list above
            3. Default if uncertain: \(defaultCalendar)

            Classification hints:
            - 병원/치과/약/건강/운동/헬스 → health or personal calendar
            - 회의/업무/보고서/미팅/deadline → work calendar
            - 학교/공부/시험/수업 → school or personal calendar
            - 가족/생일/기념일 → home or personal calendar
            """)

        let maxAttempts = 3
        var lastResult = defaultCalendar

        for attempt in 1...maxAttempts {
            let prompt: String
            if attempt == 1 {
                prompt = "Task: \(todoTitle)"
            } else {
                // 이전 답이 틀렸을 때 — 피드백과 함께 재시도
                prompt = """
                    Your previous answer "\(lastResult)" is NOT in the allowed list.
                    Allowed list: \(availableCalendars.joined(separator: ", "))
                    Task: \(todoTitle)
                    Try again — return ONLY one exact name from the list.
                    """
            }

            let response = try await session.respond(
                to: prompt,
                generating: CalendarClassification.self
            )

            let returned = response.content.calendarName
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if availableCalendars.contains(returned) {
                return returned  // 유효한 이름 → 즉시 반환
            }

            lastResult = returned  // 다음 시도에서 피드백으로 사용
        }

        // 3회 모두 실패 → 가장 유사한 이름 fuzzy 매칭 시도
        if let closest = availableCalendars.min(by: {
            editDistance($0.lowercased(), lastResult.lowercased()) <
            editDistance($1.lowercased(), lastResult.lowercased())
        }), editDistance(closest.lowercased(), lastResult.lowercased()) <= 3 {
            return closest
        }

        return defaultCalendar
    }

    // Levenshtein edit distance — fuzzy 매칭용
    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                dp[j] = a[i-1] == b[j-1] ? prev : min(prev, min(dp[j], dp[j-1])) + 1
                prev = temp
            }
        }
        return dp[b.count]
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
        #if DEBUG
        print("[AIFallback] \(error)")
        #endif
        return fallback
    }
}
