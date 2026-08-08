import Foundation

// MARK: - 정기 결제 감지
//
// 같은 가게가 일정한 간격으로 비슷한 금액을 가져가면 정기 결제로 본다.
// 사용자가 등록할 필요가 없다 — 메일에서 들어온 거래만으로 추론한다.
//
// 감지 결과로 "이번 달 남은 고정지출"을 계산해서 잔액과 붙이면
// "지금 $X 있지만 나갈 게 $Y니까 실제로 쓸 수 있는 건 $Z"가 나온다.

struct RecurringCharge: Identifiable {
    var id: String { key }
    /// 가게명을 정규화한 값 (그룹 키).
    var key: String
    var displayName: String
    var category: String
    /// 대표 금액 — 중앙값이라 한 번 튄 달에 흔들리지 않는다.
    var typicalAmount: Double
    var lastAmount: Double
    var lastDate: Date
    var occurrences: Int
    var intervalDays: Int
    var nextDueDate: Date

    /// 최근 금액이 대표값과 10% 넘게 다르면 가격이 바뀐 것으로 본다.
    var priceChanged: Bool {
        typicalAmount > 0 && abs(lastAmount - typicalAmount) / typicalAmount > 0.10
    }

    var cadenceLabel: String {
        switch intervalDays {
        case ..<10: return "매주"
        case 10..<20: return "격주"
        case 20..<45: return "매월"
        case 45..<120: return "분기"
        default: return "매년"
        }
    }

    /// 오랫동안 안 빠져나가면 해지됐을 수 있다.
    func looksDormant(asOf now: Date = .now) -> Bool {
        now.timeIntervalSince(lastDate) > Double(intervalDays) * 2.2 * 86_400
    }
}

enum RecurringDetector {

    /// 최소 관측 횟수. 2번이면 우연히 같은 가게를 두 번 간 것과 구분이 안 된다.
    private static let minimumOccurrences = 3
    private static let lookbackDays = 400

    @MainActor
    static func detect(in database: POSDatabase, asOf now: Date = .now) -> [RecurringCharge] {
        guard let amountProperty = database.amountProperty else { return [] }
        let categoryProperty = database.categoryProperty
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now

        struct Observation {
            var date: Date
            var amount: Double
            var title: String
            var category: String
        }

        var groups: [String: [Observation]] = [:]
        for entry in database.entries ?? [] {
            guard entry.countsAsSpending(in: database),
                  let amount = entry.number(for: amountProperty), amount > 0
            else { continue }
            let date = entry.effectiveDate(in: database)
            guard date >= cutoff, date <= now else { continue }
            let key = normalize(entry.title)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(
                Observation(
                    date: date,
                    amount: amount,
                    title: entry.title,
                    category: categoryProperty.flatMap { entry.text(for: $0) } ?? "기타"
                )
            )
        }

        var results: [RecurringCharge] = []
        for (key, rawObservations) in groups {
            let observations = rawObservations.sorted { $0.date < $1.date }
            guard observations.count >= minimumOccurrences else { continue }

            // 하루 안에 여러 번 결제한 건 한 번으로 친다 (같은 가게 연속 결제).
            var collapsed: [Observation] = []
            for observation in observations {
                if let last = collapsed.last,
                   Calendar.current.isDate(last.date, inSameDayAs: observation.date) {
                    continue
                }
                collapsed.append(observation)
            }
            guard collapsed.count >= minimumOccurrences else { continue }

            let gaps = zip(collapsed, collapsed.dropFirst()).map {
                $1.date.timeIntervalSince($0.date) / 86_400
            }
            guard let interval = median(gaps), interval >= 5, interval <= 400 else { continue }

            // 간격이 들쭉날쭉하면 정기 결제가 아니라 그냥 자주 가는 가게다.
            // 기준이 헐거우면 단골 카페(3일·14일·7일 간격 방문)가 "주간 구독"으로
            // 잡힌다. 진짜 구독은 청구일이 거의 고정이라 흔들림이 며칠 안 된다.
            let spread = gaps.map { abs($0 - interval) }
            guard let typicalDrift = median(spread),
                  typicalDrift <= max(2.5, interval * 0.15)
            else { continue }

            let amounts = collapsed.map(\.amount)
            guard let typical = median(amounts), typical > 0 else { continue }
            // 구독료는 거의 똑같은 금액으로 빠져나간다. 8%까지만 같은 값으로 본다
            // — 여기가 헐거우면 밥값처럼 매번 다른 지출이 섞여 들어온다.
            // 0.6으로 둔 건 요금이 오른 직후(옛 금액 2회 + 새 금액 1회)에도
            // 계속 잡히게 하기 위해서다.
            let within = amounts.filter { abs($0 - typical) / typical <= 0.08 }.count
            guard Double(within) / Double(amounts.count) >= 0.6 else { continue }

            let last = collapsed[collapsed.count - 1]
            let next = last.date.addingTimeInterval(interval * 86_400)

            results.append(
                RecurringCharge(
                    key: key,
                    displayName: last.title,
                    category: last.category,
                    typicalAmount: typical,
                    lastAmount: last.amount,
                    lastDate: last.date,
                    occurrences: collapsed.count,
                    intervalDays: Int(interval.rounded()),
                    nextDueDate: next
                )
            )
        }

        return results.sorted { $0.nextDueDate < $1.nextDueDate }
    }

    /// 이번 달에 아직 안 빠져나간 고정지출 합계.
    static func remainingThisMonth(_ charges: [RecurringCharge], asOf now: Date = .now) -> Double {
        let calendar = Calendar.current
        guard let monthEnd = calendar.date(
            byAdding: DateComponents(month: 1, day: -1),
            to: calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        ) else { return 0 }

        return charges
            .filter { !$0.looksDormant(asOf: now) }
            .filter { $0.nextDueDate > now && $0.nextDueDate <= calendar.date(byAdding: .day, value: 1, to: monthEnd)! }
            .map(\.typicalAmount)
            .reduce(0, +)
    }

    /// 한 달 기준으로 환산한 고정지출 총액 (주간·연간도 월로 맞춘다).
    static func monthlyEquivalent(_ charges: [RecurringCharge], asOf now: Date = .now) -> Double {
        charges
            .filter { !$0.looksDormant(asOf: now) }
            .map { $0.typicalAmount * (30.0 / Double(max($0.intervalDays, 1))) }
            .reduce(0, +)
    }

    // MARK: 도우미

    /// 가게 이름을 그룹 키로 정규화한다. 영수증 문자열은 매번 조금씩 달라서
    /// (`UBER EATS`, `UBER   EATS 4821`) 숫자와 공백을 걷어내야 묶인다.
    static func normalize(_ title: String) -> String {
        var value = title.uppercased()
        value = value.replacingOccurrences(of: "[0-9]+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "[^A-Z가-힣 ]+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
