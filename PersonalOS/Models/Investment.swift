import SwiftData
import Foundation

@Model
final class Investment {
    var id: UUID
    var ticker: String
    var name: String
    var shares: Double
    var averageCost: Double    // 주당 평균 매입가
    var currency: String       // "USD" | "KRW"
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ticker: String,
        name: String,
        shares: Double,
        averageCost: Double,
        currency: String = "USD",
        createdAt: Date = .now
    ) {
        self.id = id
        self.ticker = ticker
        self.name = name
        self.shares = shares
        self.averageCost = averageCost
        self.currency = currency
        self.createdAt = createdAt
    }

    var totalCost: Double { shares * averageCost }

    // currentPrice는 절대 저장하지 않음 — 항상 API에서 실시간 조회
    func unrealizedPnL(currentPrice: Double) -> Double {
        (currentPrice - averageCost) * shares
    }

    func unrealizedPnLPercent(currentPrice: Double) -> Double {
        guard averageCost > 0 else { return 0 }
        return ((currentPrice - averageCost) / averageCost) * 100
    }

    func currentValue(currentPrice: Double) -> Double {
        shares * currentPrice
    }
}
