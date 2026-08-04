import Foundation

// MARK: - Email → transaction
//
// Deliberately conservative: a message only becomes a 가계부 row if it matches
// one of the headline sentences below. Chase sends plenty of mail that merely
// *mentions* a dollar amount ("Payment amount $530.13" in an autopay
// confirmation), and a loose `\$[0-9.]+` rule would happily invent a
// transaction from every one of them.

struct ParsedTransaction {
    /// Merchant string exactly as the bank wrote it — kept for auditing.
    var merchantRaw: String
    /// Cleaned-up name used as the entry title.
    var title: String
    var amount: Double
    var date: Date
    /// One of `EntryKind`.
    var kind: String
    var method: String
    /// Identifies the pattern that matched, e.g. "chase.card".
    var ruleID: String
    var messageID: String
    var note: String = ""
}

/// A group of senders the importer knows how to read. The user can switch
/// whole groups on and off in settings.
enum MailSource: String, CaseIterable, Identifiable {
    case chase
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chase: return "Chase 알림"
        case .apple: return "Apple 영수증"
        }
    }

    var detail: String {
        switch self {
        case .chase: return "카드 결제 · 송금 · 청구서 결제 · 입금 · Zelle"
        case .apple: return "구독·앱 구매 영수증 (Chase 알림과 중복될 수 있어요)"
        }
    }

    /// Values handed to IMAP `SEARCH FROM`, which matches on a substring of
    /// the From header. Narrow enough to skip the marketing mail, wide enough
    /// to survive a change of subdomain.
    var searchSenders: [String] {
        switch self {
        case .chase: return ["alerts@chase.com"]
        case .apple: return ["no_reply@email.apple.com"]
        }
    }

    /// Domains accepted after the message is fetched, so a lookalike sender
    /// that slipped through a fuzzy server-side search is dropped.
    var senderDomains: [String] {
        switch self {
        case .chase: return ["chase.com"]
        case .apple: return ["email.apple.com", "apple.com"]
        }
    }

    static func matching(domain: String) -> MailSource? {
        allCases.first { source in
            source.senderDomains.contains { domain == $0 || domain.hasSuffix("." + $0) }
        }
    }
}

enum TransactionParser {

    /// Chase notices that legitimately mention a dollar amount without being a
    /// transaction. Listing them keeps the "we couldn't read this" counter
    /// meaningful instead of firing on every autopay confirmation.
    private static let benignPhrases = [
        "Payment scheduled", "automatic payments", "was canceled", "was cancelled",
        "credit report", "score goal", "Credit Journey", "Identity Monitoring",
        "as a recipient", "Zelle® settings", "Zelle ® settings",
        "statement is now available", "Connected Banking", "Security alert",
        "signed in with a new device", "credit card application",
        "Paperless enrollment", "new notice or letter", "Social Security number",
    ]

    /// True when a message is from a known source and carries an `Amount $…`
    /// label, isn't one of the known non-transaction notices, and still matched
    /// no rule — i.e. probably a bank alert in a format we don't read yet.
    /// Surfaced in the sync summary so a new Chase alert type doesn't just
    /// silently disappear.
    static func looksUnrecognized(_ message: MIMEMessage) -> Bool {
        guard MailSource.matching(domain: message.senderDomain) != nil else { return false }
        let haystack = message.subject + " " + message.text
        for phrase in benignPhrases where haystack.localizedCaseInsensitiveContains(phrase) {
            return false
        }
        return firstMatch(in: message.text, patterns: ["\\bAmount \\$[0-9,]+\\.[0-9]{2}"]) != nil
    }

    /// Returns nil for anything that isn't a recognized money movement.
    static func parse(_ message: MIMEMessage) -> ParsedTransaction? {
        guard let source = MailSource.matching(domain: message.senderDomain),
              MailSettings.isEnabled(source.id)
        else { return nil }

        switch source {
        case .chase: return parseChase(message)
        case .apple: return parseApple(message)
        }
    }

    // MARK: Chase

    private static func parseChase(_ message: MIMEMessage) -> ParsedTransaction? {
        let text = message.text
        let fallbackDate = message.date ?? .now
        let account = capture("Account ending in \\(?\\D{0,4}(\\d{4})\\)?", in: text, group: 1)
        let method = account.map { "Chase ···\($0)" } ?? "Chase"

        // 1. Zelle money in.
        if let payer = capture("payment\\s+(.+?)\\s+sent you money", in: text, group: 1),
           let amount = amount(in: text, pattern: "Amount \\$([0-9,]+\\.[0-9]{2})") {
            var note = capture("Memo\\s+(.+?)\\s+is registered", in: text, group: 1) ?? ""
            note = note.replacingOccurrences(of: payer, with: "").trimmingCharacters(in: .whitespaces)
            let name = clean(payer)
            return ParsedTransaction(
                merchantRaw: payer,
                title: name,
                amount: amount,
                date: chaseDate(in: text) ?? fallbackDate,
                // 룸메 정산이 대부분이라 기본은 '받은 정산' — 잔액엔 더해지고
                // 월 수입 통계는 부풀지 않는다. 진짜 수입이면 검토 큐에서 바꾸면 된다.
                kind: EntryKind.settleIn,
                method: method.appending(" · Zelle"),
                ruleID: "chase.zelle-in",
                messageID: message.messageID ?? "",
                note: note
            )
        }

        // 2. Deposit posted — payroll, direct deposit, mobile check deposit.
        //    Chase ships this alert off by default, so it only fires once the
        //    user turns "Deposit posted" on at chase.com/alerts. The exact
        //    wording is unverified against a real message, so match only the
        //    headline phrase and take the payer from the label table.
        if let headline = firstMatch(
            in: text,
            patterns: [
                "You received an? (?:direct )?deposit of \\$([0-9,]+\\.[0-9]{2})",
                "Your (?:direct )?deposit of \\$([0-9,]+\\.[0-9]{2})",
                "An? (?:direct )?deposit of \\$([0-9,]+\\.[0-9]{2}) (?:was|has been) (?:posted|made|credited)",
            ]
        ) {
            let payer = capture("(?:Description|From|Payer|Received from)\\s+(.+?)\\s+Amount \\$", in: text, group: 1)
                ?? "입금"
            let value = amount(in: text, pattern: "Amount \\$([0-9,]+\\.[0-9]{2})") ?? number(headline[1])
            guard let value else { return nil }
            return ParsedTransaction(
                merchantRaw: payer,
                title: clean(payer),
                amount: value,
                date: chaseDate(in: text) ?? fallbackDate,
                kind: EntryKind.income,
                method: method.appending(" · 입금"),
                ruleID: "chase.deposit",
                messageID: message.messageID ?? ""
            )
        }

        // 3. Card purchase — both the debit ("transaction of $X with Y") and
        //    credit ("a $X transaction with Y") phrasings.
        if let headline = firstMatch(
            in: text,
            patterns: [
                "You made an? (?:debit card |credit card )?transaction of \\$([0-9,]+\\.[0-9]{2}) with (.+?)(?= Account ending| Card ending| Made on|$)",
                "You made an? \\$([0-9,]+\\.[0-9]{2}) transaction with (.+?)(?= Account ending| Card ending| Made on|$)",
            ]
        ) {
            let merchant = capture("Description\\s+(.+?)\\s+Amount \\$", in: text, group: 1)
                ?? headline[2]
                ?? ""
            let value = amount(in: text, pattern: "Amount \\$([0-9,]+\\.[0-9]{2})")
                ?? number(headline[1])
            guard let value, !merchant.isEmpty else { return nil }
            return ParsedTransaction(
                merchantRaw: merchant,
                title: clean(merchant),
                amount: value,
                date: chaseDate(in: text) ?? fallbackDate,
                kind: EntryKind.expense,
                method: method,
                ruleID: "chase.card",
                messageID: message.messageID ?? ""
            )
        }

        // 4. Bill payment.
        if let headline = firstMatch(
            in: text,
            patterns: ["Your bill payment of \\$([0-9,]+\\.[0-9]{2}) to (.+?)(?= Account ending| Made on|$)"]
        ) {
            let recipient = capture("Recipient\\s+(.+?)\\s+Amount \\$", in: text, group: 1)
                ?? headline[2]
                ?? ""
            let value = amount(in: text, pattern: "Amount \\$([0-9,]+\\.[0-9]{2})") ?? number(headline[1])
            guard let value, !recipient.isEmpty else { return nil }
            return ParsedTransaction(
                merchantRaw: recipient,
                title: clean(recipient),
                amount: value,
                date: chaseDate(in: text) ?? fallbackDate,
                kind: EntryKind.expense,
                method: method.appending(" · 청구서"),
                ruleID: "chase.bill",
                messageID: message.messageID ?? ""
            )
        }

        // 5. Outgoing transfer / Zelle payment.
        if let headline = firstMatch(
            in: text,
            patterns: ["You sent \\$([0-9,]+\\.[0-9]{2}) to (.+?)(?= Account ending| Sent on| with Zelle|$)"]
        ) {
            let recipient = capture("Recipient\\s+(.+?)\\s+Amount \\$", in: text, group: 1)
                ?? headline[2]
                ?? ""
            let value = amount(in: text, pattern: "Amount \\$([0-9,]+\\.[0-9]{2})") ?? number(headline[1])
            guard let value, !recipient.isEmpty else { return nil }
            return ParsedTransaction(
                merchantRaw: recipient,
                title: clean(recipient),
                amount: value,
                date: chaseDate(in: text) ?? fallbackDate,
                kind: EntryKind.expense,
                method: method.appending(" · 송금"),
                ruleID: "chase.transfer",
                messageID: message.messageID ?? ""
            )
        }

        return nil
    }

    /// `Made on Jul 31, 2026 at 5:18 PM ET` / `Sent on Jul 27, 2026`
    private static func chaseDate(in text: String) -> Date? {
        guard let match = firstMatch(
            in: text,
            patterns: ["(?:Made|Sent|Posted|Received) on ([A-Z][a-z]{2} [0-9]{1,2}, [0-9]{4})(?: at ([0-9]{1,2}:[0-9]{2} [AP]M) ([A-Z]{2,4}))?"]
        ) else { return nil }

        guard let day = match[1] else { return nil }
        let zone = timeZone(abbreviation: match[3])

        if let time = match[2] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "MMM d, yyyy h:mm a"
            if let date = formatter.date(from: "\(day) \(time)") { return date }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.date(from: day)
    }

    /// Chase writes "ET"/"CT" rather than the "EST"/"EDT" that
    /// `TimeZone(abbreviation:)` understands, so map the common ones by hand.
    private static func timeZone(abbreviation: String?) -> TimeZone {
        guard let abbreviation, !abbreviation.isEmpty else { return .current }
        switch abbreviation.uppercased() {
        case "ET", "EST", "EDT": return TimeZone(identifier: "America/New_York") ?? .current
        case "CT", "CST", "CDT": return TimeZone(identifier: "America/Chicago") ?? .current
        case "MT", "MST", "MDT": return TimeZone(identifier: "America/Denver") ?? .current
        case "PT", "PST", "PDT": return TimeZone(identifier: "America/Los_Angeles") ?? .current
        default: return TimeZone(abbreviation: abbreviation.uppercased()) ?? .current
        }
    }

    // MARK: Apple

    /// Apple receipts arrive in the account's language — Sihoon's are Korean —
    /// and list one or more line items. We take the order total.
    private static func parseApple(_ message: MIMEMessage) -> ParsedTransaction? {
        let text = message.text
        let subject = message.subject
        let looksLikeReceipt = subject.contains("영수증")
            || subject.lowercased().contains("receipt")
            || subject.lowercased().contains("your invoice")
        guard looksLikeReceipt else { return nil }

        guard let total = amount(in: text, pattern: "(?:합계|총계|TOTAL|Total)\\s*\\$?([0-9,]+\\.[0-9]{2})")
            ?? lastAmount(in: text)
        else { return nil }

        let item = capture("(Apple\\s?(?:Music|Arcade|One|Care One|TV\\+|iCloud\\+?))", in: text, group: 1)
            ?? "Apple"

        return ParsedTransaction(
            merchantRaw: item,
            title: item,
            amount: total,
            date: message.date ?? .now,
            kind: EntryKind.expense,
            method: "Apple",
            ruleID: "apple.receipt",
            messageID: message.messageID ?? ""
        )
    }

    // MARK: Merchant cleanup

    private static let processorPrefixes = [
        "TST*", "TST *", "SQ *", "SQ*", "SP ", "SP*", "MDC*", "PY *", "PAYPAL *",
        "IN *", "WWW.", "GOOGLE *", "AMZN MKTP", "TOAST*",
    ]

    /// Trims payment-processor noise so the title reads like a place, not a
    /// settlement string. The untouched original is kept on the entry.
    static func clean(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        let upper = value.uppercased()
        for prefix in processorPrefixes where upper.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        for suffix in [" PENDING", " Pending"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        value = MIMEMessage.replacingMatches(of: "\\s*\\*\\s*", in: value, with: " ")
        value = MIMEMessage.replacingMatches(of: "\\s+#\\d+$", in: value, with: "")
        value = MIMEMessage.replacingMatches(of: "\\s+\\d{3}[\\s-]\\d{3}[\\s-]?\\d*$", in: value, with: "")
        value = MIMEMessage.collapseWhitespace(value)
        return value.isEmpty ? raw : value
    }

    // MARK: Regex helpers

    /// Returns the capture groups of the first pattern that matches, indexed
    /// like NSTextCheckingResult (element 0 is the whole match).
    static func firstMatch(in text: String, patterns: [String]) -> [String?]? {
        let full = text as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: full.length))
            else { continue }
            return (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return full.substring(with: range).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func capture(_ pattern: String, in text: String, group: Int) -> String? {
        guard let match = firstMatch(in: text, patterns: [pattern]), group < match.count else { return nil }
        guard let value = match[group], !value.isEmpty else { return nil }
        return value
    }

    static func amount(in text: String, pattern: String) -> Double? {
        number(capture(pattern, in: text, group: 1))
    }

    static func number(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: ""))
    }

    private static func lastAmount(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "\\$([0-9,]+\\.[0-9]{2})") else { return nil }
        let full = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: full.length))
        guard let last = matches.last else { return nil }
        return number(full.substring(with: last.range(at: 1)))
    }
}
