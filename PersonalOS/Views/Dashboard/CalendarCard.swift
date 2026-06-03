import SwiftUI
import EventKit

struct CalendarCard: View {
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Label(L.calendarTitle, systemImage: "calendar")
                .font(Theme.caption().bold())
                .foregroundStyle(.secondary)

            switch calendar.authStatus {
            case .notDetermined:
                requestAccessButton

            case .denied, .restricted:
                HStack {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(L.calendarPermission)
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L.calendarSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(Theme.caption().bold())
                }

            case .fullAccess:
                if calendar.todayEvents.isEmpty {
                    Text(L.calendarEmpty)
                        .font(Theme.body())
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: Theme.spacingXS) {
                        ForEach(calendar.todayEvents.prefix(3), id: \.eventIdentifier) { event in
                            EventRowView(event: event)
                        }
                        if calendar.todayEvents.count > 3 {
                            Text(L.calendarMore(calendar.todayEvents.count - 3))
                                .font(Theme.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .writeOnly:
                Text(L.calendarWriteOnly)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)

            @unknown default:
                EmptyView()
            }
        }
        .cardStyle()
    }

    private var requestAccessButton: some View {
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
    }
}

struct EventRowView: View {
    let event: EKEvent
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? L.calendarNoTitle)
                    .font(Theme.body())
                    .lineLimit(1)
                Text(calendar.timeString(for: event))
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
