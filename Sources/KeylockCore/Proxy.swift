import Darwin
import Foundation
import os

public enum ProxyError: Error, CustomStringConvertible {
    case bind(String)
    case message(String)

    public var description: String {
        switch self {
        case .bind(let message): "proxy bind failed: \(message)"
        case .message(let message): message
        }
    }
}

public final class LocalProxy: @unchecked Sendable {
    public let port: UInt16
    private let host: String
    private let secret: Data
    private var listenFD: Int32 = -1
    private let stopped = OSAllocatedUnfairLock(initialState: false)
    private var acceptThread: Thread?

    public init(host: String, secret: Data) throws {
        self.host = host
        self.secret = secret
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProxyError.bind("socket") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw ProxyError.bind(String(cString: strerror(errno))) }
        guard listen(fd, 16) == 0 else { throw ProxyError.bind("listen") }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard got == 0 else { throw ProxyError.bind("getsockname") }
        listenFD = fd
        port = UInt16(bigEndian: bound.sin_port)
    }

    public func start() {
        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        acceptThread = thread
        thread.start()
    }

    public func stop() {
        stopped.withLock { $0 = true }
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
    }

    private func acceptLoop() {
        while !stopped.withLock({ $0 }) {
            var clientAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(listenFD, $0, &length)
                }
            }
            if client < 0 { break }
            if clientAddress.sin_addr.s_addr != inet_addr("127.0.0.1") {
                Darwin.close(client)
                continue
            }
            handle(client)
            Darwin.close(client)
        }
    }

    private func handle(_ client: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while buffer.range(of: Data("\r\n\r\n".utf8)) == nil && buffer.count < 1024 * 1024 {
            let count = chunk.withUnsafeMutableBytes { read(client, $0.baseAddress, 8192) }
            if count <= 0 { return }
            buffer.append(contentsOf: chunk.prefix(count))
        }
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            writeStatic(client, status: 400, body: "denied")
            return
        }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        let bodyStart = headerEnd.upperBound
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            writeStatic(client, status: 400, body: "denied")
            return
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let request = lines.first?.split(separator: " ", omittingEmptySubsequences: true), request.count >= 2 else {
            writeStatic(client, status: 400, body: "denied")
            return
        }
        let method = String(request[0])
        let target = String(request[1])
        if method == "TRACE" || method == "CONNECT" {
            writeStatic(client, status: 405, body: "denied")
            return
        }
        let contentLength = headerValue("Content-Length", in: lines).flatMap(Int.init) ?? 0
        while buffer.count < bodyStart + contentLength && buffer.count < 8 * 1024 * 1024 {
            let count = chunk.withUnsafeMutableBytes { read(client, $0.baseAddress, 8192) }
            if count <= 0 { break }
            buffer.append(contentsOf: chunk.prefix(count))
        }
        let body = buffer.subdata(in: bodyStart..<min(bodyStart + contentLength, buffer.endIndex))
        guard let url = Upstream.url(host: host, target: target) else {
            writeStatic(client, status: 400, body: "denied")
            return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body.isEmpty ? nil : body
        var forwarded: Set<String> = []
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let lower = name.lowercased()
            if ["host", "authorization", "content-length", "proxy-authorization", "connection", "accept-encoding", "x-api-key"].contains(lower) {
                continue
            }
            if forwarded.contains(lower) { continue }
            forwarded.insert(lower)
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in Upstream.keyHeaders(host: host, secret: secret) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let session = Self.makeSession()
        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: urlRequest) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                box.status = http.statusCode
                for (key, value) in http.allHeaderFields {
                    let name = String(describing: key)
                    let lower = name.lowercased()
                    if ["transfer-encoding", "content-length", "connection", "authorization", "content-encoding"].contains(lower) {
                        continue
                    }
                    box.headers[name] = String(describing: value)
                }
            }
            box.body = data ?? Data()
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        session.invalidateAndCancel()
        if Redact.containsSecret(box.body, secret: secret) {
            writeStatic(client, status: 502, body: "upstream failed")
            return
        }
        writeResponse(client, status: box.status, headers: box.headers, body: box.body)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let delegate = RedirectBlocker()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private func headerValue(_ name: String, in lines: [String]) -> String? {
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].caseInsensitiveCompare(name) == .orderedSame {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func writeStatic(_ client: Int32, status: Int, body: String) {
        let data = Data(body.utf8)
        writeResponse(client, status: status, headers: ["Content-Type": "text/plain"], body: data)
    }

    private func writeResponse(_ client: Int32, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "ERROR")\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(body)
        packet.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let wrote = write(client, base.advanced(by: sent), raw.count - sent)
                if wrote <= 0 { break }
                sent += wrote
            }
        }
    }
}

public enum Upstream {
    public static func url(host: String, target: String) -> URL? {
        guard target.hasPrefix("/"), !target.hasPrefix("//") else { return nil }
        guard !target.contains("://"), !target.contains("@"), !target.contains("\\"), !target.contains(" "), !target.contains("#") else {
            return nil
        }
        guard target.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        guard path.hasPrefix("/") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = path
        if parts.count == 2 {
            components.percentEncodedQuery = String(parts[1])
        }
        guard let url = components.url, url.host == host, url.user == nil else { return nil }
        return url
    }

    public static func keyHeaders(host: String, secret: Data) -> [String: String] {
        guard let text = String(data: secret, encoding: .utf8), !text.isEmpty else { return [:] }
        if host == "api.anthropic.com" {
            return ["x-api-key": text]
        }
        return ["Authorization": "Bearer \(text)"]
    }
}

private final class ResponseBox: @unchecked Sendable {
    var status = 502
    var headers: [String: String] = [:]
    var body = Data()
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
