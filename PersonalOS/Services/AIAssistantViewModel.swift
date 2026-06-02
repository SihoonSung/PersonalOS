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

    // 사용자가 AI 탭 열 때 호출 — 최신 데이터로 컨텍스트 주입
    func startSession(contextSummary: String) {
        messages = []
        session = LanguageModelSession(instructions: """
            당신은 PersonalOS의 AI 비서입니다.
            사용자의 현재 데이터 요약:
            \(contextSummary)

            규칙:
            - 친근한 한국어로 답합니다
            - 제공된 수치만 사용하고 직접 계산하거나 추측하지 않습니다
            - 데이터에 없는 정보는 모른다고 솔직하게 말합니다
            - 답변은 간결하게 3~5문장 이내로 합니다
            """)
    }

    @MainActor
    func send() async {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, let session else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, content: userText))
        isResponding = true
        streamingText = ""

        do {
            let stream = session.streamResponse(to: userText)
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
}
