import Foundation

/// 앱 ↔ 위젯 공유 상수/모델. 위젯 타깃에도 이 파일을 멤버로 추가할 것.
enum WidgetShared {
    static let appGroupID = "group.com.calebsung.PersonalOS"
    static let snapshotFilename = "widget-snapshot.json"

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }
}

struct WidgetSnapshot: Codable {
    struct Task: Codable, Identifiable {
        var id: String
        var title: String
        var overdue: Bool
        var timeText: String?
    }

    var generatedAt: Date = .now
    var doneToday: Int = 0
    var totalToday: Int = 0
    var tasks: [Task] = []

    /// 예산 — budgetSet이 false면 monthSpentText만 의미 있음.
    var budgetSet: Bool = false
    var remainingText: String = ""
    var monthSpentText: String = ""
    var budgetProgress: Double = 0
    var overBudget: Bool = false

    static func load() -> WidgetSnapshot? {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
