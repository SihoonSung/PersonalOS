import Foundation
import EventKit
import Observation

/// 시스템 캘린더 읽기 — 대시보드 오늘 일정 카드용.
@Observable
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private(set) var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var todayEvents: [EKEvent] = []

    private init() {}

    func refresh() {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        guard authStatus == .fullAccess else {
            todayEvents = []
            return
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        todayEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        refresh()
    }

    func timeString(for event: EKEvent) -> String {
        if event.isAllDay { return "종일" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
