import SwiftUI
import SwiftData

/// 오늘 할 일 중심 메인 카드 — 진행률 + 체크 가능한 오늘/연체 목록
struct TodayFocusCard: View {
    @Environment(\.modelContext) private var context
    let database: POSDatabase
    var onOpen: () -> Void = {}

    private var calendar: Calendar { .current }

    private struct Item: Identifiable {
        let entry: POSEntry
        let due: Date?
        let priority: String?
        let overdue: Bool
        var id: UUID { entry.uuid }
    }

    private func resolve() -> (focus: [Item], doneToday: Int) {
        guard let doneProp = database.doneProperty else { return ([], 0) }
        let dateProp = database.dateProperty
        let priorityProp = database.priorityProperty
        let startOfToday = calendar.startOfDay(for: .now)

        var focus: [Item] = []
        var doneToday = 0
        for entry in database.entries ?? [] {
            if entry.bool(for: doneProp) {
                if calendar.isDateInToday(entry.updatedAt) { doneToday += 1 }
                continue
            }
            guard let due = dateProp.flatMap({ entry.date(for: $0) }) else { continue }
            let isOverdue = due < startOfToday
            guard isOverdue || calendar.isDateInToday(due) else { continue }
            focus.append(Item(
                entry: entry,
                due: due,
                priority: priorityProp.flatMap { entry.text(for: $0) },
                overdue: isOverdue
            ))
        }
        focus.sort { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        return (focus, doneToday)
    }

    var body: some View {
        let (focus, doneToday) = resolve()
        let total = focus.count + doneToday
        let progress = total == 0 ? 0 : Double(doneToday) / Double(total)

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text(L.dashTodayTitle)
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if total > 0 {
                    Text(L.dashDoneCount(doneToday, total))
                        .font(Theme.caption().bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Button(action: onOpen) {
                    Image(systemName: "chevron.right")
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if focus.isEmpty {
                Text(total == 0 ? L.dashNoTasks : L.dashAllClear)
                    .font(Theme.body())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.spacingS)
            } else {
                progressBar(progress)
                    .padding(.bottom, Theme.spacingXS)

                ForEach(focus.prefix(4)) { item in
                    row(item)
                }

                if focus.count > 4 {
                    Text(L.dashMoreTasks(focus.count - 4))
                        .font(Theme.caption())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
        }
        .glassCardStyle()
        .animation(.spring(duration: 0.35), value: focus.count)
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.glassTrack)
                Capsule()
                    .fill(Theme.glassInk.opacity(0.75))
                    .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
            }
        }
        .frame(height: 5)
        .animation(.spring(duration: 0.4), value: progress)
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: Theme.spacingS) {
            Button {
                complete(item)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if let color = priorityColor(item.priority) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }

            Text(item.entry.title.isEmpty ? "(제목 없음)" : item.entry.title)
                .font(Theme.body())
                .lineLimit(1)

            Spacer()

            if item.overdue {
                Text(L.overdueBadge)
                    .font(Theme.caption2().bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.red.opacity(0.12), in: Capsule())
            } else if let due = item.due, database.dateProperty?.config.includeTime == true {
                Text(due.formatted(.dateTime.hour().minute()))
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private func priorityColor(_ priority: String?) -> Color? {
        switch priority {
        case "높음": return Theme.priorityHigh
        case "보통": return Theme.priorityMedium
        case "낮음": return Theme.priorityLow
        default: return nil
        }
    }

    private func complete(_ item: Item) {
        guard let doneProp = database.doneProperty else { return }
        withAnimation(.spring(duration: 0.35)) {
            item.entry.setBool(true, for: doneProp, context: context)
            try? context.save()
        }
        NotionSyncService.shared.scheduleAutoSync()
        WidgetDataWriter.refresh(context: context)
    }
}
