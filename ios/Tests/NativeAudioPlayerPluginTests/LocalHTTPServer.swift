import Foundation
import Network

/// A minimal HTTP server on the loopback interface, so the tests can hand the player an http URL
/// that really is fetched over the network stack -- the path a remote audio file takes -- without
/// depending on anything outside the machine.
///
/// It serves the files it was given and nothing else, and answers byte range requests: AVPlayer
/// asks for a range before anything else and gives up on a server that ignores it.
final class LocalHTTPServer {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LocalHTTPServer")
    private var files: [String: (data: Data, contentType: String)] = [:]
    private let lock = NSLock()
    private var servedPaths: [String] = []

    /// The paths of every request that was answered with content, in order.
    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return servedPaths
    }

    private(set) var port: UInt16 = 0

    /// Starts listening, and returns once the port is known.
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        var failure: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                failure = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw URLError(.cannotConnectToHost)
        }
        if let failure {
            throw failure
        }
        port = listener.port?.rawValue ?? 0
    }

    func stop() {
        listener?.cancel()
    }

    func serve(_ data: Data, at path: String, contentType: String) {
        lock.lock()
        files[path] = (data, contentType)
        lock.unlock()
    }

    func url(for path: String) throws -> URL {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            throw URLError(.badURL)
        }
        return url
    }

    // MARK: - Connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
                self.respond(to: head, on: connection)
                // keep-alive: AVPlayer reuses the connection for its next range request
                self.receiveRequest(on: connection, buffer: Data(buffer[end.upperBound...]))
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        let method = requestLine.first.map(String.init) ?? ""
        let path = requestLine.count > 1 ? String(requestLine[1]) : "/"

        lock.lock()
        let file = files[path]
        lock.unlock()

        guard let file, method == "GET" || method == "HEAD" else {
            send(status: "404 Not Found", headers: ["Content-Length": "0"], body: Data(), on: connection)
            return
        }

        lock.lock()
        servedPaths.append(path)
        lock.unlock()

        let total = file.data.count
        var headers = [
            "Content-Type": file.contentType,
            "Accept-Ranges": "bytes"
        ]

        if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let range = byteRange(rangeLine, total: total) {
            let body = file.data.subdata(in: range.lowerBound..<(range.upperBound + 1))
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound)/\(total)"
            headers["Content-Length"] = "\(body.count)"
            send(status: "206 Partial Content", headers: headers, body: method == "HEAD" ? Data() : body, on: connection)
        } else {
            headers["Content-Length"] = "\(total)"
            send(status: "200 OK", headers: headers, body: method == "HEAD" ? Data() : file.data, on: connection)
        }
    }

    /// `Range: bytes=start-end`, `bytes=start-` or `bytes=-suffix`, as a closed range of offsets.
    private func byteRange(_ line: String, total: Int) -> ClosedRange<Int>? {
        guard let spec = line.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces),
              let dash = spec.firstIndex(of: "-") else {
            return nil
        }

        let startText = spec[..<dash]
        let endText = spec[spec.index(after: dash)...]

        if startText.isEmpty, let suffix = Int(endText) {
            return max(0, total - suffix)...(total - 1)
        }

        guard let start = Int(startText), start < total else {
            return nil
        }

        let end = Int(endText).map { min($0, total - 1) } ?? (total - 1)
        return start...end
    }

    private func send(status: String, headers: [String: String], body: Data, on connection: NWConnection) {
        var response = "HTTP/1.1 \(status)\r\n"
        for (name, value) in headers {
            response += "\(name): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
