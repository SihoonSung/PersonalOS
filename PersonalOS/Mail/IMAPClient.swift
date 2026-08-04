import Foundation
import Network

// MARK: - Minimal IMAP client
//
// Just enough IMAP to log in with an app password, find the right mailbox,
// search by sender + date, and pull whole messages. No third-party packages:
// NWConnection gives us TLS, and the wire protocol we need is a handful of
// line-oriented commands.
//
// Everything is MainActor-isolated (the project default) and fully async, so
// no thread ever blocks — the socket callbacks resume continuations instead.

enum IMAPError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case loginFailed(String)
    case commandFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "메일 서버에 연결돼 있지 않아요."
        case .connectionFailed(let detail):
            return "연결 실패: \(detail)"
        case .loginFailed(let detail):
            return "로그인 실패 — 이메일 주소와 앱 비밀번호를 확인해 주세요. (\(detail))"
        case .commandFailed(let detail):
            return "서버가 요청을 거절했어요: \(detail)"
        case .timedOut:
            return "메일 서버 응답이 없어요. 네트워크를 확인해 주세요."
        }
    }
}

/// One fetched message: the raw RFC 822 bytes plus the UID it came from.
struct RawMessage {
    var uid: UInt32
    var bytes: [UInt8]
}

final class IMAPClient {

    private let host: String
    private let port: UInt16
    private let username: String
    private let password: String
    private let timeout: TimeInterval

    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var tagCounter = 0

    init(host: String, port: Int, username: String, password: String, timeout: TimeInterval = 30) {
        self.host = host
        self.port = UInt16(port)
        self.username = username
        self.password = password
        self.timeout = timeout
    }

    // MARK: Lifecycle

    func connect() async throws {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw IMAPError.connectionFailed("포트 번호가 올바르지 않아요 (\(port))")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = connection

        try await withTimeout {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let box = ResumeBox()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if box.claim() { continuation.resume() }
                    case .waiting(let error):
                        if box.claim() {
                            continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                        }
                    case .failed(let error):
                        if box.claim() {
                            continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                        }
                    case .cancelled:
                        if box.claim() {
                            continuation.resume(throwing: IMAPError.connectionFailed("연결이 취소됐어요"))
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }
        }

        _ = try await readLine() // server greeting
    }

    func login() async throws {
        do {
            _ = try await send("LOGIN \(quoted(username)) \(quoted(password))")
        } catch IMAPError.commandFailed(let detail) {
            throw IMAPError.loginFailed(detail)
        }
    }

    func logout() async {
        _ = try? await send("LOGOUT")
        disconnect()
    }

    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    // MARK: Mailbox

    /// The mailbox that holds everything, archived included. Gmail exposes it
    /// as `[Gmail]/All Mail`, but the name is localized, so ask the server for
    /// the RFC 6154 `\All` mailbox instead of hardcoding a string.
    func allMailMailbox() async -> String {
        guard let response = try? await send("LIST (SPECIAL-USE) \"\" \"*\"") else { return "INBOX" }
        for line in response.lines where line.uppercased().contains("\\ALL") {
            if let name = Self.mailboxName(fromListLine: line) { return name }
        }
        return "INBOX"
    }

    /// Read-only select, so fetching never flips messages to \Seen.
    func examine(_ mailbox: String) async throws {
        _ = try await send("EXAMINE \(quoted(mailbox))")
    }

    // MARK: Search & fetch

    /// UIDs of messages from `sender` received on or after `since`.
    /// IMAP's SINCE is date-granular and server-local, so callers should treat
    /// the result as "roughly since" and dedupe downstream.
    func searchUIDs(from sender: String, since: Date) async throws -> [UInt32] {
        let dateString = Self.searchDateFormatter.string(from: since)
        let response = try await send("UID SEARCH SINCE \(dateString) FROM \(quoted(sender))")
        var uids: [UInt32] = []
        for line in response.lines {
            let upper = line.uppercased()
            guard upper.hasPrefix("* SEARCH") else { continue }
            let payload = line.dropFirst("* SEARCH".count)
            for token in payload.split(separator: " ") {
                if let uid = UInt32(token) { uids.append(uid) }
            }
        }
        return uids
    }

    /// Full RFC 822 source of one message. Uses BODY.PEEK so the unread state
    /// in Gmail is left exactly as the user left it.
    func fetchMessage(uid: UInt32) async throws -> RawMessage? {
        let response = try await send("UID FETCH \(uid) (BODY.PEEK[])")
        guard let bytes = response.literals.first else { return nil }
        return RawMessage(uid: uid, bytes: bytes)
    }

    // MARK: - Command plumbing

    private struct Response {
        var lines: [String] = []
        var literals: [[UInt8]] = []
        var completion = ""
    }

    @discardableResult
    private func send(_ command: String) async throws -> Response {
        tagCounter += 1
        let tag = String(format: "A%04d", tagCounter)
        try await write("\(tag) \(command)\r\n")

        var response = Response()
        while true {
            var line = try await readLine()
            while let count = Self.literalLength(in: line) {
                response.literals.append(try await readBytes(count))
                line += try await readLine()
            }
            if line.hasPrefix(tag + " ") {
                response.completion = String(line.dropFirst(tag.count + 1))
                break
            }
            response.lines.append(line)
        }

        guard response.completion.uppercased().hasPrefix("OK") else {
            throw IMAPError.commandFailed(response.completion)
        }
        return response
    }

    private func write(_ text: String) async throws {
        guard let connection else { throw IMAPError.notConnected }
        try await withTimeout {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let index = indexOfCRLF() {
                let line = Array(buffer[0..<index])
                buffer.removeFirst(index + 2)
                return String(decoding: line, as: UTF8.self)
            }
            buffer.append(contentsOf: try await receiveChunk())
        }
    }

    private func readBytes(_ count: Int) async throws -> [UInt8] {
        while buffer.count < count {
            buffer.append(contentsOf: try await receiveChunk())
        }
        let out = Array(buffer[0..<count])
        buffer.removeFirst(count)
        return out
    }

    private func indexOfCRLF() -> Int? {
        guard buffer.count >= 2 else { return nil }
        var i = 0
        while i < buffer.count - 1 {
            if buffer[i] == 13 && buffer[i + 1] == 10 { return i }
            i += 1
        }
        return nil
    }

    private func receiveChunk() async throws -> [UInt8] {
        guard let connection else { throw IMAPError.notConnected }
        return try await withTimeout {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                        return
                    }
                    if let data, !data.isEmpty {
                        continuation.resume(returning: [UInt8](data))
                        return
                    }
                    // No data, no error, not complete: nothing useful will
                    // arrive on this receive. Returning an empty chunk here
                    // would spin readLine/readBytes, so treat it as a drop.
                    continuation.resume(throwing: IMAPError.connectionFailed(
                        isComplete ? "서버가 연결을 닫았어요" : "메일 서버가 응답을 끊었어요"
                    ))
                }
            }
        }
    }

    /// Races `work` against a deadline. The socket callbacks resume checked
    /// continuations, and cancellation alone never resumes those — so on
    /// timeout we cancel the NWConnection itself, which makes the pending
    /// send/receive fail and lets the racing child finish. Without that the
    /// task group would wait forever for a child it just cancelled.
    private func withTimeout<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let seconds = timeout
        let socket = connection
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                socket?.cancel()
                throw IMAPError.timedOut
            }
            do {
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw IMAPError.timedOut
                }
                group.cancelAll()
                return result
            } catch {
                socket?.cancel()
                group.cancelAll()
                throw error
            }
        }
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Static parsing helpers

    static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter
    }()

    /// `... BODY[] {20531}` → 20531
    static func literalLength(in line: String) -> Int? {
        guard line.hasSuffix("}") else { return nil }
        guard let open = line.lastIndex(of: "{") else { return nil }
        var digits = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
        if digits.hasSuffix("+") { digits.removeLast() } // LITERAL+ form
        return Int(digits)
    }

    /// `* LIST (\HasNoChildren \All) "/" "[Gmail]/All Mail"` → `[Gmail]/All Mail`
    static func mailboxName(fromListLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("\"") {
            guard let closing = trimmed.lastIndex(of: "\"") else { return nil }
            let head = trimmed[trimmed.startIndex..<closing]
            guard let opening = head.lastIndex(of: "\"") else { return nil }
            let name = String(trimmed[trimmed.index(after: opening)..<closing])
            return name.isEmpty ? nil : name
        }
        guard let last = trimmed.split(separator: " ").last else { return nil }
        return String(last)
    }
}

/// Guards a continuation against a second resume when a connection reports
/// several terminal states in a row.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
