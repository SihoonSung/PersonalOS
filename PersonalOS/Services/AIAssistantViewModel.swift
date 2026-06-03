import Foundation
import FoundationModels

struct ChatMessage: Identifiable {
    var id: UUID = UUID()
    var role: Role
    var content: String
    var timestamp: Date = .now

    enum Role { case user, assistant }
}

@Observable
final class AIAssistantViewModel {
    var messages: [ChatMessage] = []
    var isResponding: Bool = false
    var streamingText: String = ""
    var inputText: String = ""

    private var session: LanguageModelSession?

    private var cachedSummary: String = ""

    func startSession(contextSummary: String) {
        messages = []
        cachedSummary = contextSummary
        session = LanguageModelSession(instructions: systemPrompt(contextSummary: contextSummary))
    }

    @MainActor
    func send() async {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, let session else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, content: userText))
        isResponding = true
        streamingText = ""

        // 방법 1+2: 질문 유형 감지 후 앱이 미리 계산한 답을 붙여서 전달
        let enriched = enrichedPrompt(for: userText)

        do {
            let stream = session.streamResponse(to: enriched)
            var fullText = ""
            for try await snapshot in stream {
                fullText = snapshot.content
                streamingText = fullText
            }
            messages.append(ChatMessage(role: .assistant, content: fullText))
            streamingText = ""
        } catch {
            messages.append(ChatMessage(role: .assistant, content: "죄송해요, 지금은 답변하기 어렵습니다."))
            streamingText = ""
        }

        isResponding = false
    }

    // MARK: - 방법 3: Few-shot 포함 시스템 프롬프트

    private func systemPrompt(contextSummary: String) -> String {
        """
        당신은 PersonalOS 앱의 AI 비서입니다.
        Apple 온디바이스 AI로 구동됩니다. GPT·Claude·Gemini 등 외부 서비스와 무관합니다.
        모델 정체를 물으면 "Apple 온디바이스 AI입니다"라고만 답하세요.

        --- 사용자 데이터 (이 내용만 사실로 간주) ---
        \(contextSummary)
        ---

        용어 정의:
        - 지출: 이번 달 쓴 돈
        - 수입: 이번 달 들어온 돈
        - 총 보유: 이월 + 이번 달 순손익. 이게 앱이 아는 유일한 "잔액".
        - 실제 은행 잔고는 앱이 알 수 없음.

        답변 규칙:
        1. 데이터에 있는 수치만 사용. 없으면 "데이터에 없어서 알 수 없어요"라고 말함.
        2. 수치는 데이터에 명시된 값을 그대로 인용. 직접 계산하지 않음.
        3. 친근한 한국어로 2~3문장 이내로 답함.
        4. 대화 맥락을 유지함.

        --- 답변 예시 (이 패턴을 따를 것) ---
        Q: 이번 달 얼마 썼어?
        A: 이번 달 지출은 [데이터의 지출 수치]예요. 가계부에 기록된 금액 기준이에요.

        Q: 투자 수익률이 어때?
        A: 현재 시세 데이터가 없어서 수익률은 알 수 없어요. 앱에서 투자 탭을 새로고침해보세요.

        Q: 오늘 뭐 해야 해?
        A: 오늘 마감인 할 일은 [오늘 마감 항목들]이에요. 먼저 처리하면 좋을 것 같아요.

        Q: 계좌 잔액이 얼마야?
        A: 실제 은행 잔고는 앱에서 알 수 없어요. 앱 기준 총 보유는 [총 보유 수치]예요.

        Q: 지난달보다 더 썼어?
        A: 지난달 데이터가 없어서 비교할 수 없어요. 이번 달 지출은 [지출 수치]예요.
        ---
        """
    }

    // MARK: - 방법 1+2: 질문 유형 감지 + 앱이 계산한 데이터 보강

    private func enrichedPrompt(for question: String) -> String {
        let lower = question.lowercased()
        let type = classifyQuestion(lower)

        switch type {
        case .budget:
            return """
                [질문]: \(question)
                [관련 데이터 — 이 수치를 그대로 인용할 것]:
                \(budgetLines(from: cachedSummary))
                """
        case .task:
            return """
                [질문]: \(question)
                [관련 데이터 — 이 항목들을 그대로 인용할 것]:
                \(taskLines(from: cachedSummary))
                """
        case .investment:
            return """
                [질문]: \(question)
                [관련 데이터]:
                \(investmentLines(from: cachedSummary))
                ※ 현재 시세는 앱 투자 탭에서 새로고침해야 알 수 있음. 수익률 계산 불가.
                """
        case .goal:
            return """
                [질문]: \(question)
                [관련 데이터]:
                \(goalLines(from: cachedSummary))
                """
        case .general:
            return question
        }
    }

    private enum QuestionType {
        case budget, task, investment, goal, general
    }

    private func classifyQuestion(_ lower: String) -> QuestionType {
        let budgetKeywords = ["지출", "수입", "얼마", "가계부", "소비", "잔액", "보유", "순손익", "이월",
                              "spent", "income", "budget", "balance", "money", "spend"]
        let taskKeywords = ["할 일", "할일", "마감", "연체", "오늘", "급한", "task", "todo", "due", "overdue", "today"]
        let investmentKeywords = ["투자", "주식", "종목", "수익률", "포트폴리오", "invest", "stock", "portfolio", "profit"]
        let goalKeywords = ["목표", "goal", "달성", "진행", "progress"]

        if budgetKeywords.contains(where: { lower.contains($0) }) { return .budget }
        if taskKeywords.contains(where: { lower.contains($0) }) { return .task }
        if investmentKeywords.contains(where: { lower.contains($0) }) { return .investment }
        if goalKeywords.contains(where: { lower.contains($0) }) { return .goal }
        return .general
    }

    // 전체 요약 문자열에서 섹션별로 관련 줄만 추출
    private func budgetLines(from summary: String) -> String {
        extractSection(from: summary, keywords: ["가계부", "지출", "수입", "순손익", "이월", "총 보유"])
    }

    private func taskLines(from summary: String) -> String {
        extractSection(from: summary, keywords: ["할 일", "미완료", "오늘 마감", "연체"])
    }

    private func investmentLines(from summary: String) -> String {
        extractSection(from: summary, keywords: ["투자", "종목", "주,", "평균단가"])
    }

    private func goalLines(from summary: String) -> String {
        extractSection(from: summary, keywords: ["목표", "달성", "%"])
    }

    private func extractSection(from summary: String, keywords: [String]) -> String {
        let lines = summary.components(separatedBy: .newlines)
        let relevant = lines.filter { line in
            keywords.contains { line.contains($0) }
        }
        return relevant.isEmpty ? "(관련 데이터 없음)" : relevant.joined(separator: "\n")
    }
}
