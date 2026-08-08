import Foundation

// MARK: - 스크린샷 → 거래 한 건
//
// Chase는 Zelle **송금 성공** 건에 대해 알림 메일을 보내지 않는다. 취소·수취인
// 변경·만료는 오는데 성공만 빠진다(계좌 이체 알림은 $1.00 최소 임계값으로 이미
// 켜져 있는데도 Zelle는 그 카테고리에 안 들어간다). 그래서 이메일 파이프라인으로는
// 영영 잡을 수 없다.
//
// 대신 송금 직후 화면을 스크린샷 찍어 공유하면 여기서 읽는다.
//
// **설계 원칙 — 메일 파서와 다르다.**
// 메일 파서(TransactionParser)는 확인된 헤드라인 문장이 정확히 맞을 때만
// 거래를 만든다. 잘못 읽으면 사용자 모르게 가계부가 오염되기 때문이다.
// 여기는 반대로 **느슨하게 읽고 반드시 사람에게 보여준다**. 결과가 확인 시트에
// 채워질 뿐 저장은 사람이 누른다. 그래서 Zelle뿐 아니라 Venmo·Cash App·
// 영수증 사진까지 같은 코드로 커버할 수 있다.
//
// 파서를 고칠 때는 `Tools/tests/receipt_parse_check.py` 를 같이 고칠 것.

/// 스크린샷 한 장에서 읽어낸 것. 전부 optional — 못 읽으면 사람이 채운다.
nonisolated struct ReceiptScan: Codable, Equatable, Sendable {
    var amount: Double?
    /// 받는 사람 / 가맹점.
    var counterparty: String?
    var date: Date?
    var memo: String?
    /// 화면에서 알아낸 출처. "Zelle" · "Venmo" · "" 등.
    var source: String = ""
    /// EntryKind 값. 확인 시트의 초기 선택.
    var suggestedKind: String = EntryKind.expense
    /// OCR 원문 — 확인 시트에서 접어서 보여준다. 잘못 읽었을 때 근거가 된다.
    var lines: [String] = []

    var isEmpty: Bool { amount == nil && counterparty == nil }
}

nonisolated enum ReceiptTextParser {

    // MARK: 입구

    static func parse(lines rawLines: [String], now: Date = .now) -> ReceiptScan {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")

        var scan = ReceiptScan()
        scan.lines = lines
        scan.source = source(in: joined)
        scan.amount = amount(in: lines)
        scan.counterparty = counterparty(in: lines)
        scan.date = date(in: lines, now: now)
        scan.memo = memo(in: lines)
        scan.suggestedKind = kind(in: joined, source: scan.source)
        return scan
    }

    // MARK: 금액

    /// 라벨이 붙은 줄을 먼저 믿고, 없으면 가장 큰 금액을 고른다.
    ///
    /// 잔액 줄은 반드시 걸러야 한다 — 통장 잔고가 송금액보다 큰 게 보통이라
    /// "가장 큰 금액" 규칙이 그대로 잔고를 집어간다.
    static func amount(in lines: [String]) -> Double? {
        var labelled: [Double] = []
        var others: [Double] = []

        for (index, line) in lines.enumerated() {
            let values = amounts(in: line)
            guard !values.isEmpty else { continue }
            if isBalanceLine(line) { continue }

            let previous = index > 0 ? lines[index - 1] : ""
            if isAmountLabel(line) || isAmountLabel(previous) {
                labelled.append(contentsOf: values)
            } else {
                others.append(contentsOf: values)
            }
        }

        // 라벨 줄에 값이 여러 개면 큰 쪽(수수료 $0.00 같은 걸 피한다).
        if let best = labelled.max() { return best }
        return others.max()
    }

    /// "Amount" 라벨만 있고 금액은 다음 줄에 있는 레이아웃이 흔해서
    /// 앞 줄도 같이 본다.
    private static func isAmountLabel(_ line: String) -> Bool {
        let upper = line.uppercased()
        for token in ["AMOUNT", "TOTAL", "YOU SENT", "YOU PAID", "SENT", "금액", "합계", "송금액", "보낸 금액"]
        where upper.contains(token) { return true }
        return false
    }

    private static func isBalanceLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        for token in ["BALANCE", "AVAILABLE", "LIMIT", "REMAINING", "잔액", "잔고", "한도"]
        where upper.contains(token) { return true }
        return false
    }

    /// 한 줄 안의 모든 금액. 소수 두 자리를 요구해서 "1394" 같은 메모 숫자를 피한다.
    static func amounts(in line: String) -> [Double] {
        matches("\\$?\\s?([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)\\.([0-9]{2})(?![0-9])", in: line)
            .compactMap { groups in
                guard groups.count > 2,
                      let whole = groups[1]?.replacingOccurrences(of: ",", with: ""),
                      let fraction = groups[2]
                else { return nil }
                return Double("\(whole).\(fraction)")
            }
    }

    // MARK: 상대

    private static let counterpartyLabels = [
        "TO", "RECIPIENT", "SENT TO", "PAID TO", "PAY TO", "받는 사람", "받는사람", "수취인", "받는분",
    ]

    /// 상대 찾기 — **확실한 단서부터** 본다.
    ///
    /// 순서가 중요하다. 실제 Chase Zelle 확인 화면(IMG_0751)에는 To 라벨도,
    /// Amount 라벨도, 날짜도 없다. 대신 이렇게 생겼다:
    ///
    ///     Confirmation
    ///     We're sending your money now. Uzma Abbas will get it
    ///     in a few minutes.
    ///     $876.55
    ///     Uzma Abbas
    ///     Registered as UZMA ABBAS
    ///     (631) 922-2291
    ///     Add a Siri shortcut, such as "Pay Uzma," to save time when sending money.
    ///
    /// 맨 아래 안내 문장에 **"to save time..."** 이 있어서, 느슨한 `to` 규칙을
    /// 먼저 돌리면 받는 사람을 "save time when sending money." 로 읽는다.
    /// 그래서 `to` 규칙은 마지막으로 밀고, **금액이 같은 줄에 있거나 You sent /
    /// You paid 로 시작할 때만** 적용한다.
    static func counterparty(in lines: [String]) -> String? {
        registeredName(in: lines)
            ?? recipientFromSentence(in: lines)
            ?? labelledName(in: lines)
            ?? inlineToName(in: lines)
    }

    /// "Registered as UZMA ABBAS" 바로 **윗줄**이 보기 좋은 표기의 이름이다.
    /// 윗줄을 못 쓰면 등록명이라도 쓴다.
    private static func registeredName(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard line.uppercased().hasPrefix("REGISTERED AS") else { continue }
            if index > 0, let cleaned = clean(lines[index - 1]) { return cleaned }
            let rest = String(line.dropFirst("Registered as".count))
            if let cleaned = clean(rest) { return cleaned }
        }
        return nil
    }

    /// "We're sending your money now. Uzma Abbas will get it" 형태.
    /// 마침표 뒤 마지막 조각만 남기면 이름이 된다 — 문장이 줄바꿈으로 잘려도
    /// 앞부분만 있으면 되므로 안전하다.
    private static func recipientFromSentence(in lines: [String]) -> String? {
        for line in lines {
            for marker in [" will get it", " will receive it", " 님이 받", "에게 보내"] {
                guard let range = line.range(of: marker, options: .caseInsensitive) else { continue }
                let head = String(line[line.startIndex..<range.lowerBound])
                let tail = head.components(separatedBy: ". ").last ?? head
                if let cleaned = clean(tail) { return cleaned }
            }
        }
        return nil
    }

    /// To / Recipient / 받는 사람 라벨.
    private static func labelledName(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard let rest = afterLabel(line, labels: counterpartyLabels) else { continue }
            if let cleaned = clean(rest) { return cleaned }
            // 라벨만 있고 값이 아래 줄에 있는 배치. 버튼 글자가 사이에 낄 수
            // 있어 몇 줄 더 본다 — clean()이 장식은 걸러낸다.
            for next in index + 1 ..< min(index + 4, lines.count) {
                if let cleaned = clean(lines[next]) { return cleaned }
            }
        }
        return nil
    }

    /// "You sent $23.00 to BILT PAYMENT" 처럼 한 줄 안에 있는 형태.
    ///
    /// **금액이 있거나 송금 동사로 시작하는 줄에만** 건다. 그냥 `to` 를 물면
    /// 화면의 안내 문장을 이름으로 읽는다 (위 설명 참고).
    private static func inlineToName(in lines: [String]) -> String? {
        for line in lines {
            let upper = line.uppercased()
            let looksLikeTransfer = !amounts(in: line).isEmpty
                || upper.hasPrefix("YOU SENT") || upper.hasPrefix("YOU PAID")
                || upper.hasPrefix("SENT TO") || upper.hasPrefix("PAID TO")
            guard looksLikeTransfer else { continue }
            guard let inline = capture(
                "\\bto\\s+([^\\n]+?)(?:\\s+Account ending|\\s+on\\s|\\s+with Zelle|$)",
                in: line, group: 1
            ) else { continue }
            if let cleaned = clean(inline) { return cleaned }
        }
        return nil
    }

    /// 화면 장식·계좌번호·연락처를 걷어낸다.
    static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = replacing("\\(\\.*\\.\\.\\.[0-9]+\\)", in: text, with: "")   // (...9601)
        text = replacing("[•*]{2,}[0-9]*", in: text, with: "")              // ••••1234
        text = replacing("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+", in: text, with: "")
        text = replacing("\\+?[0-9]{3}[-. ][0-9]{3}[-. ][0-9]{4}", in: text, with: "")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t:-–—,·"))
        guard text.count >= 2, text.count <= 60 else { return nil }
        guard !isChrome(text) else { return nil }
        // 숫자와 통화기호만 남은 건 이름이 아니다.
        guard text.rangeOfCharacter(from: CharacterSet.letters) != nil else { return nil }
        return text
    }

    /// 버튼·안내 문구처럼 이름일 리 없는 것들.
    private static func isChrome(_ text: String) -> Bool {
        let upper = text.uppercased()
        let exact: Set<String> = [
            "DONE", "OK", "CLOSE", "BACK", "CANCEL", "SHARE", "VIEW", "SEND", "SEND AGAIN",
            "CONTINUE", "NEXT", "HOME", "ACCOUNTS", "ZELLE", "VENMO", "PAY", "REQUEST",
            "CONFIRMATION", "ADD TO SIRI", "SEE DETAILS", "MEMO", "AMOUNT", "RECIPIENT",
            "확인", "닫기", "완료", "취소", "공유", "홈", "송금", "요청",
        ]
        if exact.contains(upper) { return true }
        for token in ["ACCOUNT ENDING", "AVAILABLE BALANCE", "TAP ", "SWIPE ", "WILL BE",
                      "USUALLY", "SIRI SHORTCUT", "SAVE TIME", "A FEW MINUTES", "SENDING MONEY"]
        where upper.contains(token) { return true }
        return false
    }

    // MARK: 날짜

    private static let monthNames = [
        "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
        "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
    ]

    static func date(in lines: [String], now: Date) -> Date? {
        let calendar = Calendar.current
        for line in lines {
            let upper = line.uppercased()
            if upper.contains("TODAY") || upper.contains("오늘") { return now }
            if upper.contains("YESTERDAY") || upper.contains("어제") {
                return calendar.date(byAdding: .day, value: -1, to: now)
            }

            // 2026-08-03
            if let groups = firstGroups("([0-9]{4})-([0-9]{2})-([0-9]{2})", in: line),
               let date = make(year: int(groups[1]), month: int(groups[2]), day: int(groups[3]), now: now) {
                return date
            }
            // 2026년 8월 3일
            if let groups = firstGroups("([0-9]{4})년\\s*([0-9]{1,2})월\\s*([0-9]{1,2})일", in: line),
               let date = make(year: int(groups[1]), month: int(groups[2]), day: int(groups[3]), now: now) {
                return date
            }
            // Aug 3, 2026  ·  August 3
            if let groups = firstGroups("([A-Za-z]{3,9})\\s+([0-9]{1,2})(?:,\\s*([0-9]{4}))?", in: line),
               let name = groups[1].map({ String($0.prefix(3)).uppercased() }),
               let month = monthNames[name],
               let date = make(year: groups[3].flatMap { Int($0) }, month: month, day: int(groups[2]), now: now) {
                return date
            }
            // 8/3/2026 · 8/3/26 · 08/03
            if let groups = firstGroups("([0-9]{1,2})/([0-9]{1,2})(?:/([0-9]{2,4}))?", in: line) {
                var year = groups[3].flatMap { Int($0) }
                if let y = year, y < 100 { year = 2000 + y }
                if let date = make(year: year, month: int(groups[1]), day: int(groups[2]), now: now) {
                    return date
                }
            }
        }
        return nil
    }

    /// 연도가 없으면 올해로 보되, 미래가 되면 작년으로 내린다.
    /// (12월 말에 1월 영수증을 찍는 반대 경우는 드물어서 한쪽만 본다.)
    private static func make(year: Int?, month: Int?, day: Int?, now: Date) -> Date? {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year ?? calendar.component(.year, from: now)
        components.hour = 12

        guard var date = calendar.date(from: components) else { return nil }
        if year == nil, date > now.addingTimeInterval(24 * 60 * 60) {
            components.year = (components.year ?? 0) - 1
            guard let previous = calendar.date(from: components) else { return date }
            date = previous
        }
        // 오늘이면 지금 시각을 쓴다 — 같은 날 여러 건의 순서가 유지된다.
        if calendar.isDate(date, inSameDayAs: now) { return now }
        return date
    }

    // MARK: 메모

    private static let memoLabels = ["MEMO", "NOTE", "FOR", "WHAT'S IT FOR", "메모", "내용", "적요"]

    static func memo(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard let rest = afterLabel(line, labels: memoLabels) else { continue }
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 { return trimmed }
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if next.count >= 2, !isAmountLabel(next) { return next }
            }
        }
        return nil
    }

    // MARK: 출처 · 유형

    static func source(in text: String) -> String {
        let upper = text.uppercased()
        for (token, name) in [
            ("ZELLE", "Zelle"), ("VENMO", "Venmo"), ("CASH APP", "Cash App"),
            ("PAYPAL", "PayPal"), ("APPLE CASH", "Apple Cash"), ("TOSS", "토스"), ("토스", "토스"),
        ] where upper.contains(token) { return name }

        // Chase Zelle 확인 화면에는 "Zelle" 글자가 없다 — 보라색 Z 는 로고라
        // OCR 이 못 읽는다. 대신 이 화면에만 같이 나오는 두 문구로 알아본다.
        if upper.contains("REGISTERED AS"), upper.contains("WILL GET IT") { return "Zelle" }
        return ""
    }

    /// 들어온 돈만 구분하고, 나간 돈은 전부 지출로 둔다.
    ///
    /// Zelle 송금을 "보낸 정산"으로 미리 찍고 싶었지만 실제 기록을 보면
    /// 룸메 정산도 있고 공과금 납부도 있어서 한쪽으로 몰 수 없다. 지출이
    /// 앱 전체의 기본값이라 여기서도 지출로 두고, 확인 시트가 같은 상대의
    /// 지난 기록을 보고 바꿔준다.
    static func kind(in text: String, source: String) -> String {
        let upper = text.uppercased()
        for token in ["YOU RECEIVED", "RECEIVED MONEY", "받았습니다", "입금"] where upper.contains(token) {
            return source.isEmpty ? EntryKind.income : EntryKind.settleIn
        }
        return EntryKind.expense
    }

    // MARK: 정규식 도구

    private static func afterLabel(_ line: String, labels: [String]) -> String? {
        let upper = line.uppercased()
        for label in labels {
            guard upper.hasPrefix(label) else { continue }
            let rest = String(line.dropFirst(label.count))
            let trimmed = rest.trimmingCharacters(in: CharacterSet(charactersIn: " \t:：-–—"))
            // "TODAY"가 "TO"로 잡히는 걸 막는다.
            if !rest.isEmpty, rest.first!.isLetter || rest.first!.isNumber { continue }
            return trimmed
        }
        return nil
    }

    private static func int(_ value: String?) -> Int? { value.flatMap { Int($0) } }

    private static func firstGroups(_ pattern: String, in text: String) -> [String?]? {
        matches(pattern, in: text).first
    }

    private static func capture(_ pattern: String, in text: String, group: Int) -> String? {
        guard let groups = firstGroups(pattern, in: text), group < groups.count else { return nil }
        return groups[group]
    }

    private static func matches(_ pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let full = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: full.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : full.substring(with: range)
            }
        }
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let full = text as NSString
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: full.length),
            withTemplate: replacement
        )
    }
}
