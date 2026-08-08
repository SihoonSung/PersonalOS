import Foundation

// MARK: - 앱 그룹
//
// 앱 · 위젯 · 공유 익스텐션이 파일과 UserDefaults 를 주고받는 통로.
// 익스텐션 타겟에도 들어가야 해서 의존성 없이 혼자 둔다.

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
