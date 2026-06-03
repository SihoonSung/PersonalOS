import Foundation

// MARK: - 금액 입력 정리

extension String {
    /// 숫자와 소수점 1개만 남긴 문자열. "3.5.5" → "3.55" 가 아니라 "3.5" 로 안전 처리.
    var numericSanitized: String {
        var result = ""
        var dotUsed = false
        for ch in self {
            if ch.isNumber {
                result.append(ch)
            } else if ch == "." && !dotUsed {
                result.append(ch)
                dotUsed = true
            }
        }
        return result
    }

    /// 정리된 문자열을 Double 로. 실패 시 nil.
    var sanitizedDouble: Double? {
        Double(numericSanitized)
    }
}

// MARK: - AI 없이도 동작하는 로컬 금액/통화 파서

enum AmountParser {
    /// 자연어에서 금액과(가능하면) 통화를 추출한다. AI 미지원 기기·파싱 실패 시 폴백용.
    /// 예) "스타벅스 5천원" → (5000, "KRW"), "넷플릭스 17달러" → (17, "USD"), "3만5천원" → (35000, "KRW")
    static func parse(_ raw: String, defaultCurrency: String = "KRW") -> (amount: Double, currency: String) {
        let text = raw.replacingOccurrences(of: ",", with: "")
        let lower = text.lowercased()

        let currency: String
        if lower.contains("$") || lower.contains("달러") || lower.contains("dollar") || lower.contains("usd") {
            currency = "USD"
        } else if text.contains("원") || text.contains("₩") || lower.contains("krw") {
            currency = "KRW"
        } else {
            currency = defaultCurrency
        }

        let amount = parseAmount(text)
        return (amount, currency)
    }

    /// 한국어 '만'/'천' 단위를 반영해 금액을 계산.
    static func parseAmount(_ raw: String) -> Double {
        let s = raw.replacingOccurrences(of: ",", with: "")

        if let manRange = s.range(of: "만") {
            var total: Double = 0
            let before = String(s[..<manRange.lowerBound])
            total += (firstNumber(before) ?? 1) * 10_000

            let after = String(s[manRange.upperBound...])
            if let cheonRange = after.range(of: "천") {
                let beforeCheon = String(after[..<cheonRange.lowerBound])
                total += (firstNumber(beforeCheon) ?? 1) * 1_000
            } else if let n = firstNumber(after) {
                // "3만5000원" 같은 경우
                total += n
            }
            return total
        }

        if let cheonRange = s.range(of: "천") {
            let before = String(s[..<cheonRange.lowerBound])
            return (firstNumber(before) ?? 1) * 1_000
        }

        return firstNumber(s) ?? 0
    }

    /// 문자열에서 첫 번째 (소수 포함) 숫자를 추출.
    private static func firstNumber(_ text: String) -> Double? {
        var current = ""
        var found: String?
        for ch in text {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else if !current.isEmpty {
                found = current
                break
            }
        }
        if found == nil, !current.isEmpty { found = current }
        guard let token = found else { return nil }
        return Double(token.numericSanitized)
    }
}
