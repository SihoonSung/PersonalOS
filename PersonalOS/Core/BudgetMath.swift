import Foundation

// MARK: - 실효 월 예산
//
// 받은 정산은 "이미 낸 돈을 돌려받은 것"이다. `EntryKind` 규칙상 지출/수입
// 통계에는 안 잡히지만(§3-1), **그 달에 실제로 더 쓸 수 있는 돈**인 건 맞다.
//
// 예: 룸메 몫까지 공과금 $876 을 내면 지출 $876 이 예산을 깎는다. 며칠 뒤
// 룸메가 $438 을 Zelle 로 보내오면 내 실부담은 $438 인데 예산은 $876 을 쓴
// 것으로 남는다. 그래서 받은 정산만큼 그 달 예산을 올린다.
//
// **지출에서 빼지 않고 예산에 더하는 이유.**
// 지출에서 빼면 카테고리 분해와 일별 추이가 같이 흔들린다 — 애초에 어느
// 카테고리에서 빼야 할지도 알 수 없다. 예산 쪽만 올리면 "얼마 썼나"는 사실
// 그대로 두고 "얼마까지 쓸 수 있나"만 맞출 수 있다.
//
// 이 계산은 대시보드 카드·가계부 화면·위젯 세 곳에서 쓰이므로 반드시 여기
// 한 군데만 고칠 것. 한 곳만 고치면 화면마다 남은 예산이 달라진다.

enum BudgetMath {

    static let key = "monthlyBudget"

    /// 사용자가 설정한 기본 예산. 뷰 밖(위젯 스냅샷)에서 읽을 때 쓴다.
    static var base: Double { UserDefaults.standard.double(forKey: key) }

    /// 그 달에 받은 정산 합계.
    static func settledIn(
        in database: POSDatabase,
        month: Date,
        calendar: Calendar = .current
    ) -> Double {
        (database.entries ?? []).reduce(0) { partial, entry in
            guard entry.kind(in: database) == EntryKind.settleIn else { return partial }
            guard calendar.isDate(
                entry.effectiveDate(in: database),
                equalTo: month,
                toGranularity: .month
            ) else { return partial }
            let amount = database.amountProperty.flatMap { entry.number(for: $0) } ?? 0
            return partial + abs(amount)
        }
    }

    /// 실효 예산 = 설정 예산 + 그 달 받은 정산.
    ///
    /// 예산을 안 정했으면(0) 정산이 있어도 0 그대로 둔다. 정산만으로 예산이
    /// 생겨버리면 "예산 미설정" 상태의 안내가 사라져서 더 헷갈린다.
    static func effective(
        base: Double,
        database: POSDatabase,
        month: Date,
        calendar: Calendar = .current
    ) -> Double {
        guard base > 0 else { return 0 }
        return base + settledIn(in: database, month: month, calendar: calendar)
    }
}
