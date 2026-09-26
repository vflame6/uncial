import Foundation
import Network

/// An HTTP server on 127.0.0.1 for loader tests. A route answers a GET the way its `Reply` says:
/// a whole body, a body streamed in chunks (up to a length or until the client goes), or the headers
/// and a few bytes followed by nothing. It counts the body bytes each path put on the wire.
final class LoopbackHTTPServer: @unchecked Sendable {
    enum Reply: Sendable {
        case body(contentType: String, Data)
        /// `chunk` over and over, `total` bytes in all (nil: until the client goes), announced with a
        /// Content-Length of `declaredLength` (nil: none, the body ends when the connection does).
        case stream(contentType: String, chunk: Data, total: Int?, declaredLength: Int?)
        /// The headers and `bytes`, then silence.
        case stall(contentType: String, bytes: Data)
    }

    private let listener: NWListener
    private let routes: [String: Reply]
    private let queue = DispatchQueue(label: "uncial-tests-http")
    private let lock = NSLock()
    private var sentBytes: [String: Int] = [:]
    private var connections: [NWConnection] = []

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(routes: [String: Reply]) throws {
        self.routes = routes
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    /// The body bytes sent for `path` so far, all connections together.
    func sent(_ path: String) -> Int {
        lock.withLock { sentBytes[path, default: 0] }
    }

    func start() async {
        let ready = AsyncStream<Void> { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    continuation.yield()
                    continuation.finish()
                default:
                    break
                }
            }
        }
        listener.start(queue: queue)
        for await _ in ready { break }
    }

    func stop() {
        listener.cancel()
        for connection in lock.withLock({ connections }) { connection.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                self.respond(to: path, on: connection)
            } else if error == nil, !isComplete {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to path: String, on connection: NWConnection) {
        guard let reply = routes[path] else {
            send(Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), on: connection) {
                connection.cancel()
            }
            return
        }
        switch reply {
        case let .body(type, data):
            send(head(type, length: data.count), on: connection) {
                self.send(body: data, for: path, on: connection) { connection.cancel() }
            }
        case let .stream(type, chunk, total, declared):
            send(head(type, length: declared), on: connection) {
                self.stream(chunk, remaining: total, for: path, on: connection)
            }
        case let .stall(type, bytes):
            send(head(type, length: nil), on: connection) {
                self.send(body: bytes, for: path, on: connection) {}
            }
        }
    }

    private func head(_ type: String, length: Int?) -> Data {
        var lines = ["HTTP/1.1 200 OK", "Content-Type: \(type)", "Connection: close"]
        if let length { lines.append("Content-Length: \(length)") }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private func send(_ data: Data, on connection: NWConnection, then next: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            if error == nil { next() }
        })
    }

    private func send(body data: Data, for path: String, on connection: NWConnection, then next: @escaping @Sendable () -> Void) {
        send(data, on: connection) { [weak self] in
            self?.count(data.count, for: path)
            next()
        }
    }

    private func stream(_ chunk: Data, remaining: Int?, for path: String, on connection: NWConnection) {
        if let remaining, remaining <= 0 {
            connection.cancel()
            return
        }
        let piece = remaining.map { chunk.prefix($0) } ?? chunk
        send(body: piece, for: path, on: connection) { [weak self] in
            self?.stream(chunk, remaining: remaining.map { $0 - piece.count }, for: path, on: connection)
        }
    }

    private func count(_ bytes: Int, for path: String) {
        lock.withLock { sentBytes[path, default: 0] += bytes }
    }
}
