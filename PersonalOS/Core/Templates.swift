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

enum Templates {

    /// Seeds default databases on first launch (no-op if any database exists).
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<POSDatabase>())) ?? 0
        guard count == 0 else { return }

        context.insert(makeBudget(sortIndex: 0))
        context.insert(makeTodo(sortIndex: 1))
        try? context.save()
    }

    /// Schema mirrors the user's Notion 가계부 database so Notion sync
    /// maps 1:1 by property name.
    static func makeBudget(sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: "가계부", icon: "💸", sortIndex: sortIndex, templateKey: TemplateKey.budget)
        var currency = PropertyConfig.empty
        currency.numberFormat = .currency
        currency.currencyCode = "USD"

        var category = PropertyConfig.empty
        category.selectOptions = ["식비", "교통/차", "주거/공과금", "구독", "쇼핑", "의료", "금융", "기타"]

        db.properties = [
            POSProperty(name: "금액", type: .number, sortIndex: 0, config: currency),
            POSProperty(name: "카테고리", type: .select, sortIndex: 1, config: category),
            POSProperty(name: "날짜", type: .date, sortIndex: 2),
            POSProperty(name: "결제수단", type: .text, sortIndex: 3),
            POSProperty(name: "출처 이메일", type: .text, sortIndex: 4),
            POSProperty(name: "확인됨", type: .checkbox, sortIndex: 5),
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

    /// Notion "📏 신체 기록"과 속성명 1:1 — 연결 시 그대로 매핑.
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

    /// Notion "📒 표현 노트"와 속성명 1:1 — 연결 시 그대로 매핑.
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

    /// Notion "🏋️ 운동 기록"과 속성명 1:1 — 부위는 다중 선택.
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

    /// An empty user database with a sensible starter column.
    static func makeBlank(name: String, sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: name, icon: "🗂️", sortIndex: sortIndex)
        db.properties = [
            POSProperty(name: "메모", type: .text, sortIndex: 0)
        ]
        return db
    }
}
