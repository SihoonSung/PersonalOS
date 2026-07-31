#if os(macOS)
import Foundation
import Network
import SwiftData

/// Minimal MCP server (Streamable HTTP transport) embedded in the Mac app.
/// External AI agents (Claude 등) connect to http://127.0.0.1:<port>/mcp
/// and read/write the user's databases through well-defined tools.
///
/// Localhost-only by design. One HTTP request per connection (Connection: close).
nonisolated final class MCPServer: @unchecked Sendable {
    static let shared = MCPServer()

    private var listener: NWListener?
    private var container: ModelContainer?
    private(set) var isRunning = false

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
    }

    func start(port: Int) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback  // never exposed to the network
        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - HTTP plumbing

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = Self.parseHTTP(buffer) {
                self.process(request: request, connection: connection)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer: buffer)
            }
        }
    }

    /// Returns (method, path, body) once the full request has arrived.
    private static func parseHTTP(_ data: Data) -> (method: String, path: String, body: Data)? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        let body = data[bodyStart...]
        guard body.count >= contentLength else { return nil }  // wait for more
        return (String(parts[0]), String(parts[1]), Data(body.prefix(contentLength)))
    }

    private func respond(_ connection: NWConnection, status: String, body: Data?) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body?.count ?? 0)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        if let body { payload.append(body) }
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - JSON-RPC dispatch

    private func process(request: (method: String, path: String, body: Data), connection: NWConnection) {
        guard request.method == "POST" else {
            respond(connection, status: "405 Method Not Allowed", body: nil)
            return
        }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            respond(connection, status: "400 Bad Request", body: nil)
            return
        }

        let method = message["method"] as? String ?? ""
        let id = message["id"]

        // Notifications get 202 with no body
        if id == nil {
            respond(connection, status: "202 Accepted", body: nil)
            return
        }

        Task { @MainActor in
            let result: [String: Any]
            switch method {
            case "initialize":
                result = [
                    "protocolVersion": "2025-03-26",
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "PersonalOS", "version": "1.0.0"],
                ]
            case "ping":
                result = [:]
            case "tools/list":
                result = ["tools": MCPTools.definitions]
            case "tools/call":
                let params = message["params"] as? [String: Any] ?? [:]
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                result = self.callTool(name: name, args: args)
            default:
                self.sendError(connection, id: id, code: -32601, message: "Method not found: \(method)")
                return
            }
            self.sendResult(connection, id: id, result: result)
        }
    }

    private func sendResult(_ connection: NWConnection, id: Any?, result: [String: Any]) {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
        respond(connection, status: "200 OK", body: data)
    }

    private func sendError(_ connection: NWConnection, id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0", "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
        respond(connection, status: "200 OK", body: data)
    }

    // MARK: - Tool execution

    @MainActor
    private func callTool(name: String, args: [String: Any]) -> [String: Any] {
        guard let container else {
            return MCPTools.errorResult("서버가 초기화되지 않았습니다.")
        }
        let context = container.mainContext
        do {
            let text = try MCPTools.execute(name: name, args: args, context: context)
            return [
                "content": [["type": "text", "text": text]],
                "isError": false,
            ]
        } catch {
            return MCPTools.errorResult("\(error.localizedDescription)")
        }
    }
}
#endif
