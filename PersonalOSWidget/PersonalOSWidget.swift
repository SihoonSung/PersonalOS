import WidgetKit
import SwiftUI

// PersonalOS 홈 화면 위젯 — 오늘 할 일 + 예산.
// 이 폴더의 파일들 + PersonalOS/Core/WidgetSnapshot.swift를
// 위젯 타깃 멤버로 추가할 것.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? WidgetSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.doneToday = 2
        s.totalToday = 5
        s.tasks = [
            Task(id: "1", title: "회의 준비", overdue: false, timeText: "15:00"),
            Task(id: "2", title: "보험 서류 제출", overdue: true, timeText: nil),
            Task(id: "3", title: "장보기", overdue: false, timeText: nil),
        ]
        s.budgetSet = true
        s.remainingText = "$873"
        s.budgetProgress = 0.71
        return s
    }
}

// MARK: - 오늘 할 일 위젯

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("오늘")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.totalToday > 0 {
                    Text("\(snapshot.doneToday)/\(snapshot.totalToday)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if snapshot.totalToday > 0 {
                ProgressView(value: Double(snapshot.doneToday), total: Double(max(snapshot.totalToday, 1)))
                    .tint(.primary.opacity(0.75))
            }

            if snapshot.tasks.isEmpty {
                Spacer()
                Text(snapshot.totalToday == 0 ? "등록된 할 일이 없어요" : "모두 끝냈어요 🎉")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(snapshot.tasks.prefix(family == .systemSmall ? 2 : 4)) { task in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(task.title)
                            .font(.footnote)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if task.overdue {
                            Text("연체")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(.red.opacity(0.12), in: Capsule())
                        } else if let time = task.timeText {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘 할 일")
        .description("오늘 마감/연체 할 일과 진행률")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 예산 위젯

struct BudgetWidgetView: View {
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("예산")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if snapshot.budgetSet {
                Text(snapshot.remainingText)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(snapshot.overBudget ? Color.orange : Color.primary)
                Text(snapshot.overBudget ? "예산 초과" : "남은 예산")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ProgressView(value: snapshot.budgetProgress)
                    .tint(snapshot.overBudget ? .orange : .primary.opacity(0.75))
            } else {
                Text(snapshot.monthSpentText.isEmpty ? "—" : snapshot.monthSpentText)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("이번 달 지출")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgetWidget", provider: SnapshotProvider()) { entry in
            BudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("예산")
        .description("남은 예산과 사용률")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Bundle

@main
struct PersonalOSWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        BudgetWidget()
    }
}
