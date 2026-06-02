import Foundation

struct QuoteResult {
    var ticker: String
    var currentPrice: Double
    var previousClose: Double
    var currency: String

    var dayChangePercent: Double {
        guard previousClose > 0 else { return 0 }
        return ((currentPrice - previousClose) / previousClose) * 100
    }

    var dayChange: Double { currentPrice - previousClose }
}

actor StockPriceService {
    // Yahoo Finance v8 비공식 엔드포인트 — API 키 불필요 (~2000 req/day)
    // 비공식 API이므로 설정 화면에 면책 고지 필요
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart/"

    func fetchPrice(ticker: String) async throws -> QuoteResult {
        guard let url = URL(string: "\(baseURL)\(ticker)?interval=1d&range=2d") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chart = json["chart"] as? [String: Any],
            let results = chart["result"] as? [[String: Any]],
            let first = results.first,
            let meta = first["meta"] as? [String: Any]
        else {
            throw URLError(.cannotParseResponse)
        }

        let currentPrice = meta["regularMarketPrice"] as? Double ?? 0
        let previousClose = meta["previousClose"] as? Double ?? 0
        let currency = meta["currency"] as? String ?? "USD"

        return QuoteResult(
            ticker: ticker,
            currentPrice: currentPrice,
            previousClose: previousClose,
            currency: currency
        )
    }

    func fetchMultiple(tickers: [String]) async -> [String: QuoteResult] {
        await withTaskGroup(of: (String, QuoteResult?).self) { group in
            for ticker in tickers {
                group.addTask {
                    let result = try? await self.fetchPrice(ticker: ticker)
                    return (ticker, result)
                }
            }
            var results: [String: QuoteResult] = [:]
            for await (ticker, result) in group {
                if let r = result { results[ticker] = r }
            }
            return results
        }
    }
}
