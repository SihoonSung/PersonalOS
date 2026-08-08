import Foundation

// MARK: - Errors

/// nonisolated: constructed inside the NotionAPI actor and thrown across
/// actor boundaries (project default isolation is MainActor).
nonisolated struct NotionAPIError: LocalizedError {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? {
        switch code {
        case "no_token": return "노션 토큰이 설정되지 않았어요."
        case "unauthorized": return "토큰이 유효하지 않아요. 다시 확인해주세요."
        case "object_not_found": return "노션에서 대상을 찾을 수 없어요. Integration이 해당 페이지에 연결돼 있는지 확인해주세요."
        default: return "노션 오류 (\(status)): \(message)"
        }
    }
}

// MARK: - Date helpers

enum NotionDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parse(_ string: String) -> Date? {
        isoFractional.date(from: string)
            ?? iso.date(from: string)
            ?? dayOnly.date(from: string)
    }

    static func dayString(_ date: Date) -> String { dayOnly.string(from: date) }
    static func isoString(_ date: Date) -> String { iso.string(from: date) }
}

// MARK: - Client

/// Minimal async Notion REST client.
/// An actor so requests are naturally serialized; throttled to stay under
/// Notion's ~3 requests/second limit, with automatic 429 retry.
actor NotionAPI {

    static let shared = NotionAPI()

    private let base = URL(string: "https://api.notion.com/v1/")!
    private let apiVersion = "2022-06-28"
    private var token: String?
    private var lastRequestAt: Date = .distantPast
    private let minInterval: TimeInterval = 0.35

    func setToken(_ newToken: String?) {
        token = (newToken?.isEmpty == true) ? nil : newToken
    }

    var hasToken: Bool { token != nil }

    // MARK: Core request

    private func request(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        retriesLeft: Int = 3
    ) async throws -> [String: Any] {
        guard let token else {
            throw NotionAPIError(status: 0, code: "no_token", message: "no token")
        }

        // Throttle.
        let wait = minInterval - Date.now.timeIntervalSince(lastRequestAt)
        if wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestAt = .now

        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError(status: 0, code: "network", message: "응답 없음")
        }

        if http.statusCode == 429, retriesLeft > 0 {
            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1.0
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            return try await request(method, path, body: body, retriesLeft: retriesLeft - 1)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw NotionAPIError(
                status: http.statusCode,
                code: json["code"] as? String ?? "unknown",
                message: json["message"] as? String ?? "알 수 없는 오류"
            )
        }
        return json
    }

    // MARK: Endpoints

    /// Validates the token. Returns the integration's display name.
    func me() async throws -> String {
        let json = try await request("GET", "users/me")
        return json["name"] as? String ?? "연결됨"
    }

    /// All databases the integration can access (paginated search).
    func searchDatabases() async throws -> [(id: String, title: String)] {
        var results: [(String, String)] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = [
                "filter": ["value": "database", "property": "object"],
                "page_size": 100,
            ]
            if let cursor { body["start_cursor"] = cursor }
            let json = try await request("POST", "search", body: body)
            for item in json["results"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String else { continue }
                let title = Self.plainText(item["title"])
                results.append((id, title.isEmpty ? "(제목 없음)" : title))
            }
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return results
    }

    /// Database object (schema lives under "properties").
    func database(id: String) async throws -> [String: Any] {
        try await request("GET", "databases/\(id)")
    }

    /// Full listing of every non-archived page in a database (paginated).
    /// Personal-scale databases only — this is a complete listing so that
    /// remote deletions can be detected reliably.
    func allPages(databaseID: String) async throws -> [[String: Any]] {
        var pages: [[String: Any]] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let json = try await request("POST", "databases/\(databaseID)/query", body: body)
            pages.append(contentsOf: json["results"] as? [[String: Any]] ?? [])
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return pages
    }

    func createPage(databaseID: String, properties: [String: Any]) async throws -> [String: Any] {
        try await request("POST", "pages", body: [
            "parent": ["database_id": databaseID],
            "properties": properties,
        ])
    }

    func updatePage(id: String, properties: [String: Any]) async throws -> [String: Any] {
        try await request("PATCH", "pages/\(id)", body: ["properties": properties])
    }

    func archivePage(id: String) async throws {
        _ = try await request("PATCH", "pages/\(id)", body: ["archived": true])
    }

    // MARK: Page body (blocks)
    //
    // 속성 동기화와 달리 본문은 **요청할 때만** 읽는다. 페이지마다 최소 한 번의
    // 왕복이 필요해서 동기화 루프에 넣으면 비용이 감당이 안 된다.

    /// 페이지(또는 블록)의 자식 블록 전체. 중첩은 따라가지 않는다 —
    /// 화면에 보여주고 뒤에 덧붙이는 용도라 최상위면 충분하다.
    func blockChildren(of blockID: String) async throws -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        var cursor: String?
        repeat {
            var path = "blocks/\(blockID)/children?page_size=100"
            if let cursor { path += "&start_cursor=\(cursor)" }
            let json = try await request("GET", path)
            blocks.append(contentsOf: json["results"] as? [[String: Any]] ?? [])
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return blocks
    }

    /// 블록을 덧붙인다. `after`를 주면 그 블록 **바로 뒤**에 끼워 넣는다
    /// (예: "📝 내 일기" 제목 아래). 없으면 페이지 맨 끝.
    ///
    /// 덧붙이기만 하고 기존 블록은 절대 건드리지 않는다 — 루틴이 만들어 둔
    /// 서식 있는 본문을 앱이 평문으로 되써서 날려버리는 사고를 막기 위함.
    func appendBlocks(to blockID: String, children: [[String: Any]], after: String? = nil) async throws {
        var body: [String: Any] = ["children": children]
        if let after { body["after"] = after }
        _ = try await request("PATCH", "blocks/\(blockID)/children", body: body)
    }

    // MARK: Helpers

    /// Concatenated plain text of a Notion rich-text / title array.
    /// nonisolated: used both inside this actor and from MainActor code.
    nonisolated static func plainText(_ value: Any?) -> String {
        guard let items = value as? [[String: Any]] else { return "" }
        return items.compactMap { $0["plain_text"] as? String }.joined()
    }
}
