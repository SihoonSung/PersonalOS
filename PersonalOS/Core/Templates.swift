import Foundation
import SwiftData

// MARK: - Built-in templates
//
// 가계부 / 할 일 are just databases on the generic engine.
// `templateKey` lets quick-add & MCP find them even after renaming.

enum TemplateKey {
    static let budget = "budget"
    static let todo = "todo"
    static let bodyLog = "bodylog"
    static let expressions = "expressions"
    static let workout = "workout"
}

/// 가계부 "유형" 값.
///
/// 네 값 각각이 두 가지를 **혼자서** 결정한다: 잔액에 더할지 뺄지, 그리고
/// 월 지출/수입 통계에 낄지. 방향이 애매한 "이체" 하나로 두면 Zelle 정산금이
/// 들어온 건지 나간 건지 알 수 없어서 잔액을 계산할 수 없다.
enum EntryKind {
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

enum Templates {

    static let budgetCategories = [
        "식비", "교통/차", "주거/공과금", "구독", "쇼핑", "의료", "금융", "기타",
    ]

    /// Seeds default databases on first launch (no-op if any database exists).
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<POSDatabase>())) ?? 0
        guard count == 0 else { return }

        context.insert(makeBudget(sortIndex: 0))
        context.insert(makeTodo(sortIndex: 1))
        try? context.save()
    }

    /// Brings older 가계부 databases up to the current schema.
    /// Adds only what's missing, so a renamed or hand-edited database survives.
    @MainActor
    static func migrate(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<POSDatabase>())) ?? []
        guard let budget = all.first(where: { $0.templateKey == TemplateKey.budget }) else { return }

        var nextIndex = (budget.orderedProperties.map(\.sortIndex).max() ?? -1) + 1
        var changed = false

        // 기본 인자를 두지 않는다 — 기본 인자 식은 nonisolated 컨텍스트에서
        // 계산돼서 MainActor 격리된 `PropertyConfig.empty`를 못 읽는다.
        func ensure(_ name: String, _ type: PropertyType, _ config: PropertyConfig) {
            guard !budget.orderedProperties.contains(where: { $0.name == name }) else { return }
            let property = POSProperty(name: name, type: type, sortIndex: nextIndex, config: config)
            property.database = budget
            context.insert(property)
            nextIndex += 1
            changed = true
        }

        var kind = PropertyConfig.empty
        kind.selectOptions = EntryKind.all
        ensure("유형", .select, kind)
        ensure("출처 이메일", .text, .empty)
        ensure("확인됨", .checkbox, .empty)

        if let kindProperty = budget.orderedProperties.first(where: { $0.name == "유형" }) {
            // Keep the select options in step with EntryKind as it evolves.
            var config = kindProperty.config
            if config.selectOptions != EntryKind.all {
                config.selectOptions = EntryKind.all
                kindProperty.config = config
                changed = true
            }
            for entry in budget.entries ?? [] {
                switch entry.text(for: kindProperty) {
                case nil, "":
                    // Rows predating 유형 — treat as 지출 so month totals
                    // don't silently change under the user.
                    entry.setText(EntryKind.expense, for: kindProperty, context: context)
                    changed = true
                case EntryKind.legacyTransfer:
                    entry.setText(EntryKind.settleIn, for: kindProperty, context: context)
                    changed = true
                default:
                    break
                }
            }
        }

        if changed { try? context.save() }
    }

    static func makeBudget(sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: "가계부", icon: "💸", sortIndex: sortIndex, templateKey: TemplateKey.budget)
        var currency = PropertyConfig.empty
        currency.numberFormat = .currency
        currency.currencyCode = "USD"

        var category = PropertyConfig.empty
        category.selectOptions = budgetCategories

        var kind = PropertyConfig.empty
        kind.selectOptions = EntryKind.all

        db.properties = [
            POSProperty(name: "금액", type: .number, sortIndex: 0, config: currency),
            POSProperty(name: "카테고리", type: .select, sortIndex: 1, config: category),
            POSProperty(name: "날짜", type: .date, sortIndex: 2),
            POSProperty(name: "유형", type: .select, sortIndex: 3, config: kind),
            POSProperty(name: "결제수단", type: .text, sortIndex: 4),
            POSProperty(name: "출처 이메일", type: .text, sortIndex: 5),
            POSProperty(name: "확인됨", type: .checkbox, sortIndex: 6),
        ]
        return db
    }

    static func makeTodo(sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: "할 일", icon: "✅", sortIndex: sortIndex, templateKey: TemplateKey.todo)

        var priority = PropertyConfig.empty
        priority.selectOptions = ["높음", "보통", "낮음"]

        var due = PropertyConfig.empty
        due.includeTime = true

        db.properties = [
            POSProperty(name: "완료", type: .checkbox, sortIndex: 0),
            POSProperty(name: "마감", type: .date, sortIndex: 1, config: due),
            POSProperty(name: "우선순위", type: .select, sortIndex: 2, config: priority),
            POSProperty(name: "메모", type: .text, sortIndex: 3),
        ]
        return db
    }

    /// 신체 기록 템플릿.
    static func makeBodyLog(sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: "신체 기록", icon: "📏", sortIndex: sortIndex, templateKey: TemplateKey.bodyLog)
        db.properties = [
            POSProperty(name: "날짜", type: .date, sortIndex: 0),
            POSProperty(name: "체중 (lb)", type: .number, sortIndex: 1),
            POSProperty(name: "체지방률 (%)", type: .number, sortIndex: 2),
            POSProperty(name: "메모", type: .text, sortIndex: 3),
        ]
        return db
    }

    /// 표현 노트 템플릿.
    static func makeExpressions(sortIndex: Int) -> POSDatabase {
        var level = PropertyConfig.empty
        level.selectOptions = ["🌱 새로움", "🔁 복습 중", "✅ 체득"]

        var source = PropertyConfig.empty
        source.selectOptions = ["일기 교정", "오늘의 표현", "직접 추가"]

        let db = POSDatabase(name: "표현 노트", icon: "📒", sortIndex: sortIndex, templateKey: TemplateKey.expressions)
        db.properties = [
            POSProperty(name: "뜻/뉘앙스", type: .text, sortIndex: 0),
            POSProperty(name: "예문", type: .text, sortIndex: 1),
            POSProperty(name: "숙련도", type: .select, sortIndex: 2, config: level),
            POSProperty(name: "출처", type: .select, sortIndex: 3, config: source),
            POSProperty(name: "추가일", type: .date, sortIndex: 4),
        ]
        return db
    }

    /// 운동 기록 템플릿 — 부위는 다중 선택.
    static func makeWorkout(sortIndex: Int) -> POSDatabase {
        var parts = PropertyConfig.empty
        parts.selectOptions = ["가슴", "등", "어깨", "하체", "팔", "코어", "심폐"]

        var kind = PropertyConfig.empty
        kind.selectOptions = ["웨이트", "유산소", "혼합"]

        let db = POSDatabase(name: "운동 기록", icon: "🏋️", sortIndex: sortIndex, templateKey: TemplateKey.workout)
        db.properties = [
            POSProperty(name: "날짜", type: .date, sortIndex: 0),
            POSProperty(name: "부위", type: .multiSelect, sortIndex: 1, config: parts),
            POSProperty(name: "유형", type: .select, sortIndex: 2, config: kind),
            POSProperty(name: "메모", type: .text, sortIndex: 3),
            POSProperty(name: "분석됨", type: .checkbox, sortIndex: 4),
        ]
        return db
    }

    /// 노션 "✅ Tasks"와 속성명 1:1.
    ///
    /// templateKey를 비워 둔 건 의도적이다 — 노션 Tasks는 완료를 체크박스가
    /// 아니라 "상태" select로 표현해서, 체크박스를 전제로 만든 할 일 화면과
    /// 맞지 않는다. 범용 목록으로 열리고 항목을 눌러 상태를 바꾸는 방식.
    static func makeNotionTasks(sortIndex: Int) -> POSDatabase {
        var pillar = PropertyConfig.empty
        pillar.selectOptions = ["Personal", "Work", "Study"]

        var status = PropertyConfig.empty
        status.selectOptions = ["할 일", "진행 중", "완료"]

        let db = POSDatabase(name: "Tasks", icon: "✅", sortIndex: sortIndex)
        db.properties = [
            POSProperty(name: "상태", type: .select, sortIndex: 0, config: status),
            POSProperty(name: "마감", type: .date, sortIndex: 1),
            POSProperty(name: "Pillar", type: .select, sortIndex: 2, config: pillar),
        ]
        return db
    }

    /// An empty user database with a sensible starter column.
    static func makeBlank(name: String, sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: name, icon: "🗂️", sortIndex: sortIndex)
        db.properties = [
            POSProperty(name: "메모", type: .text, sortIndex: 0)
        ]
        return db
    }
}
