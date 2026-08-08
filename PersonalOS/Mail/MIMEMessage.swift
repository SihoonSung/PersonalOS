import Foundation

// MARK: - Just-enough MIME
//
// Bank alert emails are simple: a couple of headers and either a text/plain
// body or a multipart/alternative with an HTML twin. This parser handles that
// shape (recursively, so nested multiparts work) and flattens whatever it
// finds into one plain-text string the transaction parsers can regex over.

struct MIMEMessage {

    var headers: [String: String] = [:]
    /// Body flattened to plain text, whitespace collapsed to single spaces.
    var text: String = ""

    var messageID: String? { headers["message-id"].map(MIMEMessage.normalizeMessageID) }
    var from: String { headers["from"] ?? "" }
    var subject: String { MIMEMessage.decodeEncodedWords(headers["subject"] ?? "") }

    var senderDomain: String {
        guard let at = from.lastIndex(of: "@") else { return "" }
        let tail = from[from.index(after: at)...]
        return tail
            .prefix { $0 != ">" && $0 != " " && $0 != "," }
            .lowercased()
    }

    var date: Date? {
        guard let raw = headers["date"] else { return nil }
        return MIMEMessage.parseRFC5322Date(raw)
    }

    // MARK: Entry point

    static func parse(_ bytes: [UInt8]) -> MIMEMessage {
        let (headerBytes, bodyBytes) = splitHeaders(bytes)
        var message = MIMEMessage()
        message.headers = parseHeaders(headerBytes)
        message.text = collapseWhitespace(flatten(bodyBytes, headers: message.headers))
        return message
    }

    // MARK: Headers

    private static func splitHeaders(_ bytes: [UInt8]) -> ([UInt8], [UInt8]) {
        // Look for CRLFCRLF first, then LFLF for servers that normalize.
        if let index = firstIndex(of: [13, 10, 13, 10], in: bytes) {
            return (Array(bytes[0..<index]), Array(bytes[(index + 4)...]))
        }
        if let index = firstIndex(of: [10, 10], in: bytes) {
            return (Array(bytes[0..<index]), Array(bytes[(index + 2)...]))
        }
        return (bytes, [])
    }

    private static func parseHeaders(_ bytes: [UInt8]) -> [String: String] {
        let raw = String(decoding: bytes, as: UTF8.self)
        var unfolded: [String] = []
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if unfolded.isEmpty {
                    unfolded.append(String(line))
                } else {
                    unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
                }
            } else if !line.isEmpty {
                unfolded.append(String(line))
            }
        }

        var headers: [String: String] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // First occurrence wins — trace headers repeat, the ones we care about don't.
            if headers[name] == nil { headers[name] = value }
        }
        return headers
    }

    /// `nonisolated` — 순수 문자열 변환이라 어느 컨텍스트에서 불러도 되고,
    /// `map(MIMEMessage.normalizeMessageID)`처럼 함수를 값으로 넘길 때
    /// MainActor 격리 경고가 뜨지 않게 한다.
    nonisolated static func normalizeMessageID(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t"))
    }

    // MARK: Body

    /// Decodes one MIME entity into plain text, recursing into multiparts and
    /// preferring text/plain over text/html at every level.
    private static func flatten(_ bytes: [UInt8], headers: [String: String]) -> String {
        let contentType = (headers["content-type"] ?? "text/plain").lowercased()

        if contentType.contains("multipart/"), let boundary = parameter("boundary", in: headers["content-type"] ?? "") {
            var plain: String?
            var html: String?
            for part in splitParts(bytes, boundary: boundary) {
                let (partHeaderBytes, partBodyBytes) = splitHeaders(part)
                let partHeaders = parseHeaders(partHeaderBytes)
                let partType = (partHeaders["content-type"] ?? "text/plain").lowercased()
                let rendered = flatten(partBodyBytes, headers: partHeaders)
                guard !rendered.isEmpty else { continue }
                if partType.contains("text/plain") || partType.contains("multipart/") {
                    if plain == nil { plain = rendered }
                } else if partType.contains("text/html") {
                    if html == nil { html = rendered }
                }
            }
            return plain ?? html ?? ""
        }

        guard contentType.contains("text/") || headers["content-type"] == nil else { return "" }

        let encoding = (headers["content-transfer-encoding"] ?? "7bit")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        let decoded: [UInt8]
        switch encoding {
        case "base64": decoded = decodeBase64(bytes)
        case "quoted-printable": decoded = decodeQuotedPrintable(bytes)
        default: decoded = bytes
        }

        let charset = parameter("charset", in: headers["content-type"] ?? "") ?? "utf-8"
        let body = decodeString(decoded, charset: charset)
        return contentType.contains("text/html") ? htmlToText(body) : body
    }

    private static func splitParts(_ bytes: [UInt8], boundary: String) -> [[UInt8]] {
        let delimiter = [UInt8]("--\(boundary)".utf8)
        var parts: [[UInt8]] = []
        var searchStart = 0
        var partStart: Int?

        while searchStart <= bytes.count - delimiter.count {
            guard let hit = firstIndex(of: delimiter, in: bytes, from: searchStart) else { break }
            // A boundary only counts at the start of a line.
            let atLineStart = hit == 0 || bytes[hit - 1] == 10
            if atLineStart {
                if let start = partStart, hit > start {
                    var end = hit
                    // Drop the CRLF that belongs to the delimiter, not the part.
                    if end > 0, bytes[end - 1] == 10 { end -= 1 }
                    if end > 0, bytes[end - 1] == 13 { end -= 1 }
                    if end > start { parts.append(Array(bytes[start..<end])) }
                }
                var next = hit + delimiter.count
                if next + 1 < bytes.count, bytes[next] == 45, bytes[next + 1] == 45 {
                    partStart = nil // closing --boundary--
                    break
                }
                while next < bytes.count, bytes[next] == 13 || bytes[next] == 10 { next += 1 }
                partStart = next
                searchStart = next
                continue
            }
            searchStart = hit + 1
        }

        // Truncated message with no closing delimiter — keep the tail rather
        // than silently dropping what may be the only text part.
        if let start = partStart, start < bytes.count {
            parts.append(Array(bytes[start...]))
        }
        return parts
    }

    // MARK: Transfer encodings

    static func decodeBase64(_ bytes: [UInt8]) -> [UInt8] {
        let text = String(decoding: bytes, as: UTF8.self)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) else { return bytes }
        return [UInt8](data)
    }

    static func decodeQuotedPrintable(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 61 { // '='
                if i + 2 < bytes.count,
                   let high = hexValue(bytes[i + 1]),
                   let low = hexValue(bytes[i + 2]) {
                    out.append(high << 4 | low)
                    i += 3
                    continue
                }
                // soft line break: "=\r\n" or "=\n"
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { i += 3; continue }
                if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }
            }
            out.append(byte)
            i += 1
        }
        return out
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48        // 0-9
        case 65...70: return byte - 55        // A-F
        case 97...102: return byte - 87       // a-f
        default: return nil
        }
    }

    static func decodeString(_ bytes: [UInt8], charset: String) -> String {
        let data = Data(bytes)
        let normalized = charset.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        if normalized == "utf-8" || normalized == "utf8" || normalized.isEmpty {
            return String(data: data, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(normalized as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            if let decoded = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
                return decoded
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    // MARK: RFC 2047 encoded words (=?UTF-8?B?...?=)

    static func decodeEncodedWords(_ raw: String) -> String {
        guard raw.contains("=?") else { return raw }
        let pattern = "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let full = raw as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: raw, range: NSRange(location: 0, length: full.length)) {
            result += full.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let charset = full.substring(with: match.range(at: 1))
            let kind = full.substring(with: match.range(at: 2)).uppercased()
            let payload = full.substring(with: match.range(at: 3))
            let bytes: [UInt8]
            if kind == "B" {
                bytes = decodeBase64([UInt8](payload.utf8))
            } else {
                bytes = decodeQuotedPrintable([UInt8](payload.replacingOccurrences(of: "_", with: " ").utf8))
            }
            result += decodeString(bytes, charset: charset)
            cursor = match.range.location + match.range.length
        }
        result += full.substring(from: cursor)
        return result
    }

    // MARK: HTML

    /// Strips markup down to the visible text. Style/script/head blocks go
    /// first — Chase alerts carry a few KB of CSS that would otherwise land in
    /// the middle of the text we regex over.
    static func htmlToText(_ html: String) -> String {
        var working = html
        for pattern in [
            "<!--.*?-->",
            "<style[^>]*>.*?</style>",
            "<script[^>]*>.*?</script>",
            "<head[^>]*>.*?</head>",
        ] {
            working = replacingMatches(of: pattern, in: working, with: " ")
        }
        working = replacingMatches(of: "<[^>]+>", in: working, with: " ")
        return decodeHTMLEntities(working)
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var working = text
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&#34;": "\"",
            "&reg;": "®", "&copy;": "©", "&trade;": "™", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&middot;": "·", "&bull;": "•",
        ]
        for (entity, replacement) in named {
            working = working.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        guard working.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);")
        else { return working }

        let full = working as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: working, range: NSRange(location: 0, length: full.length)) {
            result += full.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let isHex = !full.substring(with: match.range(at: 1)).isEmpty
            let digits = full.substring(with: match.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            }
            cursor = match.range.location + match.range.length
        }
        result += full.substring(from: cursor)
        return result
    }

    // MARK: Utilities

    static func collapseWhitespace(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{034F}", with: "")
            .replacingOccurrences(of: "\u{3164}", with: " ")
        return replacingMatches(of: "\\s+", in: unified, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func replacingMatches(of pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement
        )
    }

    /// `text/html; charset="UTF-8"` → `UTF-8` for `parameter("charset", ...)`.
    static func parameter(_ name: String, in headerValue: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(?:\"([^\"]*)\"|([^;\\s]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let full = headerValue as NSString
        guard let match = regex.firstMatch(in: headerValue, range: NSRange(location: 0, length: full.length)) else {
            return nil
        }
        for index in 1...2 where match.range(at: index).location != NSNotFound {
            let value = full.substring(with: match.range(at: index))
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func parseRFC5322Date(_ raw: String) -> Date? {
        var cleaned = raw.trimmingCharacters(in: .whitespaces)
        if let paren = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[cleaned.startIndex..<paren]).trimmingCharacters(in: .whitespaces)
        }
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from start: Int = 0) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        var i = max(0, start)
        let limit = haystack.count - needle.count
        while i <= limit {
            if haystack[i] == needle[0] {
                var matched = true
                for j in 1..<needle.count where haystack[i + j] != needle[j] {
                    matched = false
                    break
                }
                if matched { return i }
            }
            i += 1
        }
        return nil
    }
}
