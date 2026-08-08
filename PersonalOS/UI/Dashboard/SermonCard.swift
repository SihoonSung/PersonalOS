import SwiftUI
import SwiftData

/// 말씀 카드 — 주일엔 기록을 청하고, 주중엔 지난 주일의 적용점을 되새긴다.
///
/// 한 주에 한 번 쓰는 기능이라 그냥 두면 잊힌다. 요일에 따라 얼굴을 바꾸는 게
/// 이 카드의 전부다.
struct SermonCard: View {
    let database: POSDatabase
    var onOpen: () -> Void = {}

    private var calendar: Calendar { .current }

    private var lastSunday: Date {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
    }

    private struct Latest {
        let entry: POSEntry
        let date: Date
        let passage: String
        let application: String
    }

    private var latest: Latest? {
        let dateProp = database.dateProperty
        let passageProp = database.orderedProperties.first { $0.name == "본문" }
        let applyProp = database.orderedProperties.first { $0.name == "적용" }

        return (database.entries ?? [])
            .map { entry in
                Latest(
                    entry: entry,
                    date: dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt,
                    passage: passageProp.flatMap { entry.text(for: $0) } ?? "",
                    application: applyProp.flatMap { entry.text(for: $0) } ?? ""
                )
            }
            .max { $0.date < $1.date }
    }

    private var recordedThisSunday: Bool {
        guard let latest else { return false }
        return calendar.isDate(latest.date, inSameDayAs: lastSunday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text("말씀")
                    .font(Theme.caption().bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            }

            if !recordedThisSunday {
                Text(calendar.isDateInToday(lastSunday) ? "오늘 설교 기록하기" : "지난 주일 기록이 비어 있어요")
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(lastSunday.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
            } else if let latest {
                Text(latest.entry.title.isEmpty ? latest.passage : latest.entry.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !latest.passage.isEmpty && !latest.entry.title.isEmpty {
                    Text(latest.passage)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }

                if !latest.application.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(latest.application)
                            .font(Theme.caption())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
