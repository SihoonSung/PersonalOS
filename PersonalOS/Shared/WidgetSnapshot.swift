import Foundation

struct WidgetSnapshot: Codable {
    var todayTaskCount: Int
    var overdueCount: Int
    var todayTasks: [WidgetTask]
    var todaySpend: Double
    var monthSpend: Double
    var updatedAt: Date

    struct WidgetTask: Codable {
        var title: String
        var isCompleted: Bool
        var dueDateString: String?
    }

    static let empty = WidgetSnapshot(
        todayTaskCount: 0,
        overdueCount: 0,
        todayTasks: [],
        todaySpend: 0,
        monthSpend: 0,
        updatedAt: .now
    )
}
