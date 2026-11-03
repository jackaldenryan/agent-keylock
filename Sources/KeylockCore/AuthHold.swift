import Darwin
import Foundation
import Security

public enum AuthHoldError: Error, CustomStringConvertible {
    case message(String)

    public var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

/// The auth setting is not a file and not a Keychain item. A same-user agent can
/// plant either of those, including a Keychain item whose trusted-app list names
/// this binary. The setting lives in this process. `run` accepts it only from a
/// peer with this binary's code directory hash. If the helper is down, or the
/// peer does not match, the setting is `always`.
public enum AuthHold {
    public static let socketURL: URL = CatalogStore.directory.appendingPathComponent("auth.sock")

    public static func current() -> AuthState {
        guard let reply = try? exchange("GET"), reply.hasPrefix("STATE ") else {
            return .default
        }
        return AuthPolicy.decode(Data(reply.dropFirst("STATE ".count).utf8))
    }

    public static func replace(_ state: AuthState) throws {
        try ensureRunning()
        let payload = String(data: AuthPolicy.encode(state), encoding: .utf8) ?? "always"
        let reply = try exchange("SET \(payload)")
        guard reply == "OK" else {
            throw AuthHoldError.message("auth helper refused the new setting")
        }
    }

    public static func reply(to line: String, state: inout AuthState, trusted: Bool) -> String {
        if line == "GET" {
            guard trusted else { return "ERR" }
            let payload = String(data: AuthPolicy.encode(state), encoding: .utf8) ?? "always"
            return "STATE \(payload)"
        }
        guard trusted, line.hasPrefix("SET ") else { return "ERR" }
        let payload = String(line.dropFirst(4))
        guard payload.count <= 80, payload.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return "ERR" }
        state = AuthPolicy.decode(Data(payload.utf8))
        return "OK"
    }

    public static func serve() throws {
        setsid()
        signal(SIGPIPE, SIG_IGN)
        try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: socketURL.deletingLastPathComponent().path)
        let lockFD = open(socketURL.deletingPathExtension().appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw AuthHoldError.message("could not lock the auth helper") }
        if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            Darwin.close(lockFD)
            return
        }
        unlink(socketURL.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AuthHoldError.message("auth socket") }
        guard bindUnix(fd, path: socketURL.path), listen(fd, 16) == 0 else {
            throw AuthHoldError.message("could not listen on \(socketURL.path)")
        }
        chmod(socketURL.path, 0o600)
        var state = AuthState.default
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            handle(client, state: &state)
            Darwin.close(client)
        }
    }

    static func handle(_ client: Int32, state: inout AuthState) {
        setTimeout(client)
        guard let line = readLine(client) else { return }
        let trusted = CodeSignature.peerMatchesSelf(client)
        let response = reply(to: line, state: &state, trusted: trusted)
        _ = writeLine(client, response)
    }

    private static func ensureRunning() throws {
        if helperIsOurs() { return }
        let executable = CommandLine.arguments[0]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth-hold"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<50 {
            if helperIsOurs() { return }
            usleep(20_000)
        }
        throw AuthHoldError.message("could not start an auth helper signed as this binary. If \(socketURL.path) is in use, quit that process and try again.")
    }

    private static func helperIsOurs() -> Bool {
        (try? exchange("GET"))?.hasPrefix("STATE ") == true
    }

    private static func exchange(_ line: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AuthHoldError.message("auth socket") }
        defer { Darwin.close(fd) }
        setTimeout(fd)
        guard connectUnix(fd, path: socketURL.path) else {
            throw AuthHoldError.message("no auth helper")
        }
        guard CodeSignature.peerMatchesSelf(fd) else {
            throw AuthHoldError.message("auth helper is not this binary")
        }
        guard writeLine(fd, line), let reply = readLine(fd) else {
            throw AuthHoldError.message("auth helper did not answer")
        }
        return reply
    }

    private static func setTimeout(_ fd: Int32) {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func readLine(_ fd: Int32) -> String? {
        var bytes = [UInt8]()
        var byte: UInt8 = 0
        while bytes.count < 128 {
            let count = read(fd, &byte, 1)
            if count <= 0 { return nil }
            if byte == 10 { break }
            if byte == 13 { continue }
            bytes.append(byte)
        }
        guard bytes.count < 128 else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func writeLine(_ fd: Int32, _ line: String) -> Bool {
        var data = Data(line.utf8)
        data.append(10)
        var sent = 0
        let bytes = [UInt8](data)
        while sent < bytes.count {
            let wrote = bytes.withUnsafeBytes { raw in
                write(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if wrote <= 0 { return false }
            sent += wrote
        }
        return true
    }

    private static func bindUnix(_ fd: Int32, path: String) -> Bool {
        var addr = sockaddr_un()
        guard fill(&addr, path: path) else { return false }
        let length = socklen_t(addr.sun_len)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, length)
            }
        } == 0
    }

    private static func connectUnix(_ fd: Int32, path: String) -> Bool {
        var addr = sockaddr_un()
        guard fill(&addr, path: path) else { return false }
        let length = socklen_t(addr.sun_len)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, length)
            }
        } == 0
    }

    private static func fill(_ addr: inout sockaddr_un, path: String) -> Bool {
        let bytes = Array(path.utf8)
        guard bytes.count < 104 else { return false }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in bytes.enumerated() {
                raw[index] = byte
            }
        }
        addr.sun_len = UInt8(2 + bytes.count + 1)
        return true
    }
}

enum CodeSignature {
    static func peerMatchesSelf(_ fd: Int32) -> Bool {
        guard let mine = cdhashOfSelf(), let theirs = cdhashOfPeer(fd), !mine.isEmpty else { return false }
        return mine == theirs
    }

    private static func cdhashOfSelf() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        return cdhash(of: code)
    }

    private static func cdhashOfPeer(_ fd: Int32) -> Data? {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return nil }
        let data = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: data] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let guest else {
            return nil
        }
        return cdhash(of: guest)
    }

    private static func cdhash(of code: SecCode) -> Data? {
        guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoUnique as String] as? Data
    }
}
