import EventKit
import Foundation

private final class CalendarEventStoreObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    var hasObserver: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observer != nil
    }

    func store(_ newObserver: NSObjectProtocol) {
        lock.lock()
        observer = newObserver
        lock.unlock()
    }

    func remove() {
        lock.lock()
        let observerToRemove = observer
        observer = nil
        lock.unlock()

        if let observerToRemove {
            NotificationCenter.default.removeObserver(observerToRemove)
        }
    }
}

@Observable
@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private let parsingService = AIParsingService()
    @ObservationIgnored
    private let eventStoreObserver = CalendarEventStoreObserver()

    private(set) var authStatus: EKAuthorizationStatus = .notDetermined
    private(set) var todayEvents: [EKEvent] = []

    // 캘린더에서 이벤트가 외부적으로 변경됐을 때 호출
    // identifier: 사라진 이벤트 식별자들 — 앱에서 해당 TodoItem 처리
    var onExternalDeletion: (([String]) -> Void)?

    var isAuthorized: Bool {
        authStatus == .fullAccess || authStatus == .writeOnly
    }

    var canReadEvents: Bool {
        authStatus == .fullAccess
    }

    var writableCalendarNames: [String] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { $0.title }
    }

    var defaultCalendarName: String {
        store.defaultCalendarForNewEvents?.title ?? ""
    }

    // 앱이 알고 있는 캘린더 이벤트 식별자 목록 (외부 삭제 감지용)
    // RootView에서 주입
    var trackedIdentifiers: Set<String> = []

    init() {
        authStatus = EKEventStore.authorizationStatus(for: .event)
        if isAuthorized {
            fetchEvents()
            startObservingExternalChanges()
        }
    }

    deinit {
        eventStoreObserver.remove()
    }

    // MARK: - 권한 요청

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                fetchEvents()
                startObservingExternalChanges()
            }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - 외부 변경 감지

    private func startObservingExternalChanges() {
        guard !eventStoreObserver.hasObserver else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalCalendarChange()
            }
        }
        eventStoreObserver.store(observer)
    }

    private func handleExternalCalendarChange() {
        fetchEvents()

        // 앱이 추적 중인 이벤트 식별자 중 캘린더에서 사라진 것을 찾음
        guard canReadEvents, !trackedIdentifiers.isEmpty else { return }

        let deletedIdentifiers = trackedIdentifiers.filter { identifier in
            store.event(withIdentifier: identifier) == nil
        }

        if !deletedIdentifiers.isEmpty {
            onExternalDeletion?(Array(deletedIdentifiers))
        }
    }

    // MARK: - 이벤트 조회

    func fetchEvents() {
        guard canReadEvents else {
            todayEvents = []
            return
        }

        let cal = Calendar.current
        let now = Date.now
        let startOfToday = cal.startOfDay(for: now)
        guard let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) else { return }

        let pred = store.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: nil)
        let all = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
        todayEvents = all
    }

    // MARK: - 추가 (AI 분류 포함)

    @discardableResult
    func addEvent(for todo: TodoItem) -> String? {
        guard isAuthorized, let dueDate = todo.dueDate else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = todo.title
        event.startDate = dueDate
        event.endDate = dueDate.addingTimeInterval(3600)
        event.notes = todo.notes.isEmpty ? nil : todo.notes
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            fetchEvents()
            let identifier = event.eventIdentifier ?? ""

            // 추적 목록에 등록
            if !identifier.isEmpty { trackedIdentifiers.insert(identifier) }

            // 저장 후 AI로 캘린더 분류 (비동기 — 저장은 먼저, 분류는 나중)
            Task {
                await self.reclassifyEvent(identifier: identifier, todoTitle: todo.title)
            }

            return identifier.isEmpty ? nil : identifier
        } catch {
            return nil
        }
    }

    // AI가 분류한 캘린더로 이벤트를 이동
    private func reclassifyEvent(identifier: String, todoTitle: String) async {
        let calendars = writableCalendarNames
        let defaultName = defaultCalendarName
        guard !calendars.isEmpty, !identifier.isEmpty else { return }

        do {
            let bestCalendarName = try await parsingService.classifyCalendar(
                todoTitle: todoTitle,
                availableCalendars: calendars,
                defaultCalendar: defaultName
            )

            guard
                let event = store.event(withIdentifier: identifier),
                let targetCalendar = store.calendars(for: .event)
                    .first(where: { $0.title == bestCalendarName })
            else { return }

            event.calendar = targetCalendar
            try? store.save(event, span: .thisEvent)
            fetchEvents()
        } catch {
            // AI 분류 실패 시 기본 캘린더 유지 — 조용히 무시
        }
    }

    // MARK: - 수정

    func updateEvent(identifier: String, for todo: TodoItem) {
        guard isAuthorized else { return }
        guard let event = store.event(withIdentifier: identifier) else {
            _ = addEvent(for: todo)
            return
        }
        event.title = todo.title
        if let dueDate = todo.dueDate {
            event.startDate = dueDate
            event.endDate = dueDate.addingTimeInterval(3600)
        }
        event.notes = todo.notes.isEmpty ? nil : todo.notes
        try? store.save(event, span: .thisEvent)
        fetchEvents()
    }

    // MARK: - 삭제

    func removeEvent(identifier: String) {
        trackedIdentifiers.remove(identifier)
        guard isAuthorized else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
        fetchEvents()
    }

    // MARK: - 완료 표시

    func markEventCompleted(identifier: String) {
        guard isAuthorized else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        let completedNote = L.calendarCompletedNote
        let existing = event.notes ?? ""
        guard !existing.components(separatedBy: .newlines).contains(completedNote) else { return }
        event.notes = existing.isEmpty ? completedNote : existing + "\n" + completedNote
        try? store.save(event, span: .thisEvent)
    }

    func unmarkEventCompleted(identifier: String) {
        guard isAuthorized else { return }
        guard let event = store.event(withIdentifier: identifier) else { return }
        let completedNotes = [
            "✓ PersonalOS에서 완료됨",
            "✓ Completed in PersonalOS"
        ]
        let remaining = (event.notes ?? "")
            .components(separatedBy: .newlines)
            .filter { !completedNotes.contains($0) }
        event.notes = remaining.isEmpty ? nil : remaining.joined(separator: "\n")
        try? store.save(event, span: .thisEvent)
        fetchEvents()
    }

    // MARK: - 추적 목록 관리

    func track(identifier: String) {
        trackedIdentifiers.insert(identifier)
    }

    /// 추적 목록에서만 제거 — 캘린더 이벤트는 건드리지 않는다.
    func untrack(identifier: String) {
        trackedIdentifiers.remove(identifier)
    }

    // MARK: - 포맷 헬퍼

    func timeString(for event: EKEvent) -> String {
        if event.isAllDay { return L.calendarAllDay }
        return event.startDate.formatted(.dateTime.hour().minute())
    }
}
