import WidgetKit
import SwiftUI

// PersonalOS 위젯 — 오늘 할 일 / 예산 / 잔액 / 성경 구절 시계.
//
// 위젯 타깃 멤버로 추가할 것:
//   PersonalOS/Core/WidgetSnapshot.swift
//   PersonalOS/Core/VerseClock.swift
//   PersonalOS/Resources/verse-clock.json   ← Copy Bundle Resources 에도

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
        s.balanceSet = true
        s.balanceText = "$1,760"
        s.balanceAsOfText = "8월 2일"
        s.fixedRemainingText = "$570"
        s.freeToSpendText = "$1,190"
        s.unreviewedCount = 3
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


// MARK: - 잔액 위젯

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCircular:
            circular
        case .accessoryInline:
            Text(snapshot.balanceSet ? "남은 돈 \(snapshot.balanceText)" : "잔액 미설정")
        default:
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("남은 돈")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if snapshot.balanceSet {
                Text(snapshot.balanceText)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(snapshot.balanceNegative ? Color.red : Color.primary)

                if !snapshot.freeToSpendText.isEmpty {
                    Divider().padding(.vertical, 1)
                    Text("고정지출 \(snapshot.fixedRemainingText) 빼면")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(snapshot.freeToSpendText)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if snapshot.unreviewedCount > 0 {
                    Text("검토 \(snapshot.unreviewedCount)건")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                } else if !snapshot.balanceAsOfText.isEmpty {
                    Text("\(snapshot.balanceAsOfText) 기준")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Spacer()
                Text("앱에서 잔고를\n한 번 입력해 주세요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("남은 돈")
                .font(.caption2)
                .widgetAccentable()
            Text(snapshot.balanceSet ? snapshot.balanceText : "—")
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !snapshot.freeToSpendText.isEmpty {
                Text("쓸 수 있는 돈 \(snapshot.freeToSpendText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: "banknote")
                .font(.system(size: 11))
            Text(snapshot.balanceSet ? snapshot.balanceText : "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BalanceWidget", provider: SnapshotProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("남은 돈")
        .description("계좌 잔액과, 고정지출을 뺀 실제 가용액")
        .supportedFamilies([
            .systemSmall,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - 성경 구절 시계

struct VerseEntry: TimelineEntry {
    let date: Date
    let verse: VerseClockEntry?
}

/// 1분마다 구절이 바뀌어야 하는데, 위젯 확장을 1분마다 깨울 수는 없다.
/// 대신 한 시간치(60개) 엔트리를 미리 만들어 넘긴다 — 시스템이 이미 받아둔
/// 엔트리를 시각에 맞춰 그려주므로 하루 24번만 깨어나면 된다.
struct VerseProvider: TimelineProvider {
    private static let entriesPerBatch = 60

    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, verse: VerseClock.entry(for: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(VerseEntry(date: .now, verse: VerseClock.entry(for: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        let calendar = Calendar.current
        // 이번 분의 0초에서 시작해야 표시가 시계와 어긋나지 않는다.
        let start = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: .now)
        ) ?? .now

        var entries: [VerseEntry] = []
        for offset in 0..<Self.entriesPerBatch {
            guard let date = calendar.date(byAdding: .minute, value: offset, to: start) else { continue }
            entries.append(VerseEntry(date: date, verse: VerseClock.entry(for: date)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct VerseClockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isDimmed
    let entry: VerseEntry

    private var isCompact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: isCompact ? 34 : 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let verse = entry.verse, verse.isExact {
                    Text("\(verse.chapter):\(verse.verse)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            if let verse = entry.verse {
                Text(verse.text)
                    .font(.system(size: isCompact ? 11 : 13, design: .serif))
                    .lineSpacing(isCompact ? 1 : 2)
                    .lineLimit(isCompact ? 4 : 5)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(isDimmed ? .secondary : .primary)

                Spacer(minLength: 0)

                Text(verse.reference)
                    .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .widgetAccentable()
            } else {
                Spacer()
                Text("verse-clock.json을 위젯 타깃에 추가해 주세요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            // StandBy 야간 모드에선 시스템이 알아서 붉게 틴트한다.
            // 배경을 칠하면 그 처리가 지저분해지므로 비워둔다.
            renderingMode == .fullColor ? AnyView(Color.clear) : AnyView(Color.clear)
        }
    }
}

struct VerseClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VerseClockWidget", provider: VerseProvider()) { entry in
            VerseClockWidgetView(entry: entry)
        }
        .configurationDisplayName("말씀 시계")
        .description("지금 시각을 장:절로 읽어요 — 7:21이면 마태복음 7:21")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Bundle

@main
struct PersonalOSWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        BudgetWidget()
        BalanceWidget()
        VerseClockWidget()
    }
}
