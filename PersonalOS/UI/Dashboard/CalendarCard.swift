import SwiftUI
import EventKit

/// 오늘 일정 글래스 카드 — 이벤트 고유색 바 + 제목 + 시간.
struct CalendarCard: View {
    private var calendar: CalendarService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text(L.calendarTitle)
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            switch calendar.authStatus {
            case .notDetermined:
                Button {
                    Task { await calendar.requestAccess() }
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text(L.calendarConnect)
                            .font(Theme.body())
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

            case .denied, .restricted:
                HStack {
                    Text(L.calendarPermission)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    #if os(iOS)
                    Button(L.calendarSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(Theme.caption().bold())
                    #endif
                }

            case .fullAccess:
                if calendar.todayEvents.isEmpty {
                    Text(L.calendarEmpty)
                        .font(Theme.body())
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Theme.spacingS) {
                        ForEach(calendar.todayEvents.prefix(3), id: \.eventIdentifier) { event in
                            eventRow(event)
                        }
                        if calendar.todayEvents.count > 3 {
                            Text(L.calendarMore(calendar.todayEvents.count - 3))
                                .font(Theme.caption())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

            default:
                Text(L.calendarEmpty)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
        .onAppear { calendar.refresh() }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        HStack(spacing: Theme.spacingS) {
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor(event))
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? L.calendarNoTitle)
                    .font(Theme.body())
                    .lineLimit(1)
                Text(calendar.timeString(for: event))
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private func eventColor(_ event: EKEvent) -> Color {
        if let cg = event.calendar?.cgColor {
            return Color(cgColor: cg)
        }
        return .secondary.opacity(0.5)
    }
}
