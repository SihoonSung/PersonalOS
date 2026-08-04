import Foundation
import SwiftData

// MARK: - 계좌 잔액
//
// 은행 잔고를 직접 읽을 방법이 없으니 "기준점 + 이후 거래 가감" 방식으로
// 추정한다. 사용자가 지금 잔고를 한 번 입력하면 그 시점 이후로 들어온 거래를
// 부호대로 더해서 현재 잔액을 만든다. 어긋나면 새 기준점을 찍으면 된다.

struct BalanceSnapshot {
    var current: Double
    var anchorAmount: Double
    var anchoredAt: Date
    var appliedCount: Int
    var spentSinceAnchor: Double
    var receivedSinceAnchor: Double

    var changeSinceAnchor: Double { current - anchorAmount }
    var isStale: Bool {
        Date.now.timeIntervalSince(anchoredAt) > 30 * 24 * 60 * 60
    }
}

enum BalanceService {

    /// 가장 최근 기준점. 없으면 아직 잔액 기능을 안 쓰는 상태.
    @MainActor
    static func latestAnchor(context: ModelContext) -> POSBalanceAnchor? {
        var descriptor = FetchDescriptor<POSBalanceAnchor>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    @MainActor
    static func allAnchors(context: ModelContext) -> [POSBalanceAnchor] {
        let descriptor = FetchDescriptor<POSBalanceAnchor>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 기준점이 없으면 nil — 화면에서 "잔액 설정하기"를 띄우는 신호.
    @MainActor
    static func snapshot(database: POSDatabase, context: ModelContext) -> BalanceSnapshot? {
        guard let anchor = latestAnchor(context: context) else { return nil }
        return snapshot(database: database, anchor: anchor)
    }

    static func snapshot(database: POSDatabase, anchor: POSBalanceAnchor) -> BalanceSnapshot {
        snapshot(database: database, anchorAmount: anchor.amount, anchoredAt: anchor.recordedAt)
    }

    /// 기준점 **이후**(초과) 거래만 반영한다. 기준점을 찍는 순간 이미 반영돼 있던
    /// 거래를 두 번 빼지 않기 위한 경계 조건이다.
    ///
    /// 값으로 받는 이유: 저장 전 미리보기에서 아직 컨텍스트에 넣지 않은
    /// `@Model` 객체를 만들 필요가 없게 하려고.
    static func snapshot(
        database: POSDatabase,
        anchorAmount: Double,
        anchoredAt: Date
    ) -> BalanceSnapshot {
        var total = anchorAmount
        var count = 0
        var spent = 0.0
        var received = 0.0

        for entry in database.entries ?? [] {
            guard entry.effectiveDate(in: database) > anchoredAt else { continue }
            let delta = entry.balanceDelta(in: database)
            guard delta != 0 else { continue }
            total += delta
            count += 1
            if delta < 0 { spent += -delta } else { received += delta }
        }

        return BalanceSnapshot(
            current: total,
            anchorAmount: anchorAmount,
            anchoredAt: anchoredAt,
            appliedCount: count,
            spentSinceAnchor: spent,
            receivedSinceAnchor: received
        )
    }

    /// 새 기준점 저장. 같은 순간에 여러 번 찍히는 걸 막으려고 1분 이내의
    /// 직전 수동 기준점은 덮어쓴다.
    @MainActor
    @discardableResult
    static func setAnchor(
        amount: Double,
        at date: Date = .now,
        source: String = "manual",
        note: String = "",
        context: ModelContext
    ) -> POSBalanceAnchor {
        if let last = latestAnchor(context: context),
           last.source == source,
           abs(last.recordedAt.timeIntervalSince(date)) < 60 {
            last.amount = amount
            last.recordedAt = date
            last.note = note
            try? context.save()
            return last
        }

        let anchor = POSBalanceAnchor(amount: amount, recordedAt: date, source: source, note: note)
        context.insert(anchor)
        try? context.save()
        return anchor
    }

    @MainActor
    static func delete(_ anchor: POSBalanceAnchor, context: ModelContext) {
        context.delete(anchor)
        try? context.save()
    }
}
