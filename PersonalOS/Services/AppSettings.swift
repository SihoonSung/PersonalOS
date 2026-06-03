import Foundation

enum Currency: String, CaseIterable {
    case krw = "KRW"
    case usd = "USD"

    var symbol: String {
        switch self {
        case .krw: return "₩"
        case .usd: return "$"
        }
    }

    var label: String {
        switch self {
        case .krw: return L.currencyKRWLabel
        case .usd: return L.currencyUSDLabel
        }
    }

    func format(_ amount: Double) -> String {
        switch self {
        case .krw:
            return "₩" + (Currency.krwFormatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))")
        case .usd:
            return Currency.usdFormatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
        }
    }

    private static let krwFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()
}
