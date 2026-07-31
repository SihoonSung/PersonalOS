import Foundation
import SwiftData

// MARK: - Built-in templates
//
// 가계부 / 할 일 are just databases on the generic engine.
// `templateKey` lets quick-add & MCP find them even after renaming.

enum TemplateKey {
    static let budget = "budget"
    static let todo = "todo"
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

    /// An empty user database with a sensible starter column.
    static func makeBlank(name: String, sortIndex: Int) -> POSDatabase {
        let db = POSDatabase(name: name, icon: "🗂️", sortIndex: sortIndex)
        db.properties = [
            POSProperty(name: "메모", type: .text, sortIndex: 0)
        ]
        return db
    }
}
