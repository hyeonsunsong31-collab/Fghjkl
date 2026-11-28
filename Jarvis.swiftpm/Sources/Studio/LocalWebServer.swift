import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

/// A tiny static web server for the studio's web products, so a phone, laptop or TV on the same
/// Wi-Fi can open what Jarvis built while the app runs (no account, no cloud, no cost).
final class LocalWebServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jarvis.web-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var folder: URL?
    private var port: UInt16 = 0

    /// Serve `folder`; returns the base link (http://<Wi-Fi address>:<port>/), or nil if no
    /// port could be opened.
    func serve(_ folder: URL) async -> URL? {
        lock.lock()
        self.folder = folder.standardizedFileURL
        let running = listener != nil && port != 0
        let current = port
        lock.unlock()
        if running { return Self.link(port: current) }
        guard let opened = await open() else { return nil }
        return Self.link(port: opened)
    }

    func stop() {
        lock.lock()
        let l = listener
        listener = nil
        port = 0
        lock.unlock()
        l?.cancel()
    }

    private func open() async -> UInt16? {
        for candidate in [UInt16(8765), 8766, 8767, 0] {
            if let p = await start(on: candidate) { return p }
        }
        return nil
    }

    private func start(on candidate: UInt16) async -> UInt16? {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let endpointPort: NWEndpoint.Port = candidate == 0 ? .any : (NWEndpoint.Port(rawValue: candidate) ?? .any)
        guard let l = try? NWListener(using: parameters, on: endpointPort) else { return nil }
        l.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let ready: UInt16? = await withCheckedContinuation { (c: CheckedContinuation<UInt16?, Never>) in
            let once = ResumeOnce(c)
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(l.port?.rawValue)
                case .failed, .cancelled: once.resume(nil)
                default: break
                }
            }
            l.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { once.resume(nil) }
        }
        guard let p = ready, p != 0 else {
            l.cancel()
            return nil
        }
        lock.lock()
        listener = l
        port = p
        lock.unlock()
        return p
    }

    // MARK: Requests

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var all = buffer
            if let data { all.append(data) }
            if let end = all.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: all[all.startIndex..<end.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if error != nil || complete || all.count > 65_536 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: all)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let requestLine = head.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        var status = "200 OK"
        var body = Data()
        var type = "text/plain; charset=utf-8"
        if parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD", let file = resolve(String(parts[1])) {
            if let data = try? Data(contentsOf: file) {
                body = parts[0] == "HEAD" ? Data() : data
                type = Packager.type(forPath: file.path)
                if type.hasPrefix("text/") || type.contains("javascript") || type.contains("json") { type += "; charset=utf-8" }
            } else {
                status = "404 Not Found"
                body = Data("Not found".utf8)
            }
        } else {
            status = parts.count >= 2 ? "404 Not Found" : "400 Bad Request"
            body = Data(status.utf8)
        }
        var header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Map a request path to a file inside the served folder (never outside it).
    private func resolve(_ rawPath: String) -> URL? {
        lock.lock()
        let base = folder
        lock.unlock()
        guard let base else { return nil }
        var path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        path = path.removingPercentEncoding ?? path
        if path.hasSuffix("/") { path += "index.html" }
        let candidate = base.appendingPathComponent(String(path.drop(while: { $0 == "/" }))).standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") || candidate.path == base.path else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate.appendingPathComponent("index.html")
        }
        return candidate
    }

    // MARK: Address

    static func link(port: UInt16) -> URL? {
        URL(string: "http://\(wifiAddress() ?? "localhost"):\(port)/")
    }

    /// The device's IPv4 address on Wi-Fi (en0), else any non-loopback IPv4 address.
    static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: item.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = host.withUnsafeBufferPointer { buffer in buffer.baseAddress.map { String(cString: $0) } ?? "" }
            if ip.hasPrefix("127.") { continue }
            if name == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}

/// Resumes a continuation exactly once (listener state changes can repeat).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16?, Never>?

    init(_ c: CheckedContinuation<UInt16?, Never>) { continuation = c }

    func resume(_ value: UInt16?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
