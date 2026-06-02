import Foundation
import WidgetKit

final class WidgetDataWriter {
    static func write(_ snapshot: WidgetSnapshot) {
        guard
            let defaults = UserDefaults(suiteName: AppGroup.id),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: AppGroup.widgetSnapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: AppGroup.id),
            let data = defaults.data(forKey: AppGroup.widgetSnapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
