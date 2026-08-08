import Foundation

// MARK: - 의존성 없는 상수들
//
// 원래 Templates.swift 안에 있었는데, **공유 익스텐션(ChoiceOS)** 이 이 값들만
// 필요한데 Templates.swift 를 통째로 끌어오면 SwiftData 모델 레이어가 전부
// 딸려온다 (POSDatabase · POSProperty · PropertyConfig …). 그래서 떼어냈다.
//
// **이 파일에는 import Foundation 말고 아무것도 들이지 말 것.** 익스텐션
// 타겟에 넣을 수 있는 이유가 그거다.

enum TemplateKey {
    static let budget = "budget"
    static let todo = "todo"
    static let bodyLog = "bodylog"
    static let expressions = "expressions"
    static let workout = "workout"
    static let sermon = "sermon"
}

/// 가계부 "유형" 값.
///
/// 네 값 각각이 두 가지를 **혼자서** 결정한다: 잔액에 더할지 뺄지, 그리고
/// 월 지출/수입 통계에 낄지. 방향이 애매한 "이체" 하나로 두면 Zelle 정산금이
/// 들어온 건지 나간 건지 알 수 없어서 잔액을 계산할 수 없다.
/// nonisolated: 순수 상수 묶음인데 프로젝트 기본 격리가 MainActor라
/// 그대로 두면 기본 인자 식이나 nonisolated 파서에서 못 읽는다.
/// (`NotionAPIError` 와 같은 이유.)
nonisolated enum EntryKind {
    /// 잔액 −, 지출 통계 O
    static let expense = "지출"
    /// 잔액 +, 수입 통계 O — 급여처럼 실제로 번 돈
    static let income = "수입"
    /// 잔액 +, 통계 X — 룸메 정산처럼 대신 낸 돈을 돌려받는 것
    static let settleIn = "받은 정산"
    /// 잔액 −, 통계 X — 남에게 정산해서 돌려주는 것
    static let settleOut = "보낸 정산"

    static let all = [expense, income, settleIn, settleOut]

    /// 잔액에 반영할 부호. 모르는 값은 지출로 본다(기존 데이터 안전장치).
    static func sign(_ kind: String) -> Double {
        switch kind {
        case income, settleIn: return 1
        default: return -1
        }
    }

    static func countsAsSpending(_ kind: String) -> Bool { kind == expense }
    static func countsAsIncome(_ kind: String) -> Bool { kind == income }

    /// 예전 스키마의 "이체" — 실제로 쓰인 건 Zelle 입금뿐이라 받은 정산으로 옮긴다.
    static let legacyTransfer = "이체"
}
