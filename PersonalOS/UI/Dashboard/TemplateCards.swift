import SwiftUI
import SwiftData
import Charts

// MARK: - 템플릿별 대시보드 미니 카드
//
// 대시보드가 templateKey를 보고 자동 배치. 반폭 그리드용 컴팩트 카드들.

// MARK: 신체 기록

struct BodyLogCard: View {
    let database: POSDatabase
    var onOpen: () -> Void = {}

    private var calendar: Calendar { .current }

    private var weightProperty: POSProperty? {
        database.orderedProperties.first { $0.type == .number && $0.name.contains("체중") }
            ?? database.orderedProperties.first { $0.type == .number }
    }

    private var fatProperty: POSProperty? {
        database.orderedProperties.first { $0.type == .number && $0.name.contains("체지방") }
    }

    private var rows: [(date: Date, weight: Double)] {
        guard let prop = weightProperty else { return [] }
        let dateProp = database.dateProperty
        return (database.entries ?? []).compactMap { entry in
            guard let w = entry.number(for: prop) else { return nil }
            return (dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt, w)
        }
        .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        let data = rows

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            cardHeader(database.name, onOpen: onOpen)

            if let last = data.last {
                Text(String(format: "%.1f lb", last.weight))
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if data.count >= 2 {
                    let delta = last.weight - data[data.count - 2].weight
                    HStack(spacing: 3) {
                        Image(systemName: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%.1f lb", abs(delta)))
                            .font(Theme.caption2())
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                } else if let fatProp = fatProperty,
                          let entry = (database.entries ?? []).max(by: { $0.createdAt < $1.createdAt }),
                          let fat = entry.number(for: fatProp) {
                    Text(String(format: "체지방 %.1f%%", fat))
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                }

                if data.count >= 2 {
                    let weights = data.suffix(10)
                    let minW = weights.map(\.weight).min() ?? 0
                    let maxW = weights.map(\.weight).max() ?? 1
                    Chart(Array(weights), id: \.date) { point in
                        LineMark(
                            x: .value("날짜", point.date),
                            y: .value("체중", point.weight)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.glassInk.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: (minW - 0.5)...(maxW + 0.5))
                    .frame(height: 28)
                }
            } else {
                Text("아직 기록이 없어요")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

// MARK: 운동 기록

struct WorkoutCard: View {
    let database: POSDatabase
    var onOpen: () -> Void = {}

    private var calendar: Calendar { .current }

    private var partsProperty: POSProperty? {
        database.orderedProperties.first { $0.type == .multiSelect }
    }

    private var dated: [(date: Date, entry: POSEntry)] {
        let dateProp = database.dateProperty
        return (database.entries ?? [])
            .map { entry -> (date: Date, entry: POSEntry) in
                (dateProp.flatMap { entry.date(for: $0) } ?? entry.createdAt, entry)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let rows = dated
        let thisWeek = rows.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            cardHeader(database.name, onOpen: onOpen)

            if let last = rows.first {
                Text("이번 주 \(thisWeek)회")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("마지막 · \(relativeDay(last.date))")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)

                if let partsProp = partsProperty {
                    let parts = last.entry.textList(for: partsProp)
                    if !parts.isEmpty {
                        HStack(spacing: Theme.spacingXS) {
                            ForEach(parts.prefix(3), id: \.self) { part in
                                Text(part)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.glassTrack, in: Capsule())
                            }
                        }
                    }
                }
            } else {
                Text("아직 기록이 없어요")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private func relativeDay(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInYesterday(date) { return "어제" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        return "\(days)일 전"
    }
}

// MARK: 표현 노트

struct ExpressionsCard: View {
    let database: POSDatabase
    var onOpen: () -> Void = {}

    private var levelProperty: POSProperty? {
        database.orderedProperties.first { $0.type == .select && $0.name.contains("숙련") }
    }

    private var meaningProperty: POSProperty? {
        database.orderedProperties.first { $0.type == .text && $0.name.contains("뜻") }
            ?? database.orderedProperties.first { $0.type == .text }
    }

    var body: some View {
        let entries = database.entries ?? []
        let learned = levelProperty.map { prop in
            entries.filter { $0.text(for: prop) == "✅ 체득" }.count
        } ?? 0
        let pending = entries.count - learned
        let preview = levelProperty.flatMap { prop in
            entries
                .filter { $0.text(for: prop) != "✅ 체득" && !$0.title.isEmpty }
                .max { $0.createdAt < $1.createdAt }
        }

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            cardHeader(database.name, onOpen: onOpen)

            if entries.isEmpty {
                Text("아직 기록이 없어요")
                    .font(Theme.caption())
                    .foregroundStyle(.secondary)
            } else {
                Text("복습 대기 \(pending)")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("체득 \(learned)개")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)

                if let preview {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preview.title)
                            .font(Theme.caption().bold())
                            .lineLimit(1)
                        if let meaningProp = meaningProperty,
                           let meaning = preview.text(for: meaningProp), !meaning.isEmpty {
                            Text(meaning)
                                .font(Theme.caption2())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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

// MARK: 제네릭 (알 수 없는 사용자 DB)

struct GenericDatabaseCard: View {
    let database: POSDatabase
    var onOpen: () -> Void = {}

    var body: some View {
        let latest = (database.entries ?? []).max { $0.updatedAt < $1.updatedAt }

        VStack(alignment: .leading, spacing: Theme.spacingS) {
            cardHeader("\(database.icon) \(database.name)", onOpen: onOpen)

            Text("\(database.entryCount)개 항목")
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let latest, !latest.title.isEmpty {
                Text("최근 · \(latest.title)")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("아직 기록이 없어요")
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

// MARK: 공통 헤더

@ViewBuilder
private func cardHeader(_ title: String, onOpen: @escaping () -> Void) -> some View {
    HStack {
        Text(title)
            .font(Theme.caption().bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        Spacer()
        Image(systemName: "chevron.right")
            .font(Theme.caption())
            .foregroundStyle(.secondary)
    }
}
