import CryptoKit
import Darwin
import Foundation
import KeylockCore

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    public var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

@main
struct Keylock {
    static func main() {
        clearProxyEnvironment()
        setrlimitCoreZero()
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("keylock: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run(_ args: [String]) throws {
        guard let command = args.first else {
            throw CLIError.message(usage)
        }
        switch command {
        case "list":
            try list()
        case "show":
            guard args.count == 2 else { throw CLIError.message("usage: keylock show <id>") }
            try show(args[1])
        case "allow-host":
            guard args.count == 2 else { throw CLIError.message("usage: keylock allow-host <host>") }
            try allowHost(args[1])
        case "revoke-host":
            guard args.count == 2 else { throw CLIError.message("usage: keylock revoke-host <host>") }
            try revokeHost(args[1])
        case "add":
            try add(Array(args.dropFirst()))
        case "run":
            try runCommand(Array(args.dropFirst()))
        case "auth":
            try auth(Array(args.dropFirst()))
        case "doctor":
            try doctor()
        case "help", "-h", "--help":
            print(usage)
        default:
            throw CLIError.message(usage)
        }
    }

    static let usage = """
    usage:
      keylock list
      keylock show <id>
      keylock allow-host <host>
      keylock revoke-host <host>
      keylock add <id> --host <host> [--description <text>] [--maps-to <VAR>] [--alias <name>]
      keylock run <id> -- <command> [args...]
      keylock auth [always|never|30m|1h|3h|1d]
      keylock doctor

    The secret is never an argument. add reads it from /dev/tty after Touch ID.
    keylock auth changes how often run asks for Touch ID. Changing it requires Touch ID.
    add and allow-host always require Touch ID.
    """

    static func list() throws {
        let catalog = try CatalogStore.load()
        if catalog.keys.isEmpty {
            print("no keys in the catalog")
            return
        }
        for entry in catalog.keys {
            print("\(entry.id)\t\(entry.host)\t\(entry.mapsTo)\t\(entry.description)")
        }
    }

    static func show(_ id: String) throws {
        try KeyID.validate(id)
        let catalog = try CatalogStore.load()
        guard let entry = catalog.keys.first(where: { $0.id == id }) else {
            throw CLIError.message("no catalog entry for \(id)")
        }
        let data = try JSONEncoder.pretty.encode(entry)
        print(String(data: data, encoding: .utf8) ?? "")
    }

    static func allowHost(_ raw: String) throws {
        let host = try HostGrammar.canonicalize(raw)
        let reason = try Reasons.allowHost(host)
        fputs("Touch ID dialog is the approval. Terminal text is not.\n\(reason)\n", stderr)
        try Fingerprint.require(reason: reason)
        var hosts = try KeychainStore.loadAllowlist()
        if !hosts.contains(host) {
            hosts.append(host)
        }
        try KeychainStore.saveAllowlist(hosts)
        print("allowed \(host)")
    }

    static func revokeHost(_ raw: String) throws {
        let host = try HostGrammar.canonicalize(raw)
        let reason = try Reasons.revokeHost(host)
        fputs("Touch ID dialog is the approval. Terminal text is not.\n\(reason)\n", stderr)
        try Fingerprint.require(reason: reason)
        var hosts = try KeychainStore.loadAllowlist()
        hosts.removeAll { $0 == host }
        try KeychainStore.saveAllowlist(hosts)
        print("revoked \(host)")
    }

    static func add(_ args: [String]) throws {
        var id: String?
        var host: String?
        var description = ""
        var mapsTo = ""
        var aliases: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if id == nil && !arg.hasPrefix("--") {
                id = arg
                index += 1
                continue
            }
            switch arg {
            case "--host":
                index += 1
                guard index < args.count else { throw CLIError.message("--host needs a value") }
                host = args[index]
            case "--description":
                index += 1
                guard index < args.count else { throw CLIError.message("--description needs a value") }
                description = args[index]
            case "--maps-to":
                index += 1
                guard index < args.count else { throw CLIError.message("--maps-to needs a value") }
                mapsTo = args[index]
            case "--alias":
                index += 1
                guard index < args.count else { throw CLIError.message("--alias needs a value") }
                aliases.append(args[index])
            default:
                throw CLIError.message("unknown argument \(arg). The secret must not be an argument.")
            }
            index += 1
        }
        guard let id else { throw CLIError.message("usage: keylock add <id> --host <host>") }
        guard let host else { throw CLIError.message("--host is required") }
        try KeyID.validate(id)
        let canonical = try HostGrammar.canonicalize(host)
        let allowed = try KeychainStore.loadAllowlist()
        guard allowed.contains(canonical) else {
            throw CLIError.message("\(canonical) is not on the host list. Run keylock allow-host \(canonical) first.")
        }
        let reason = try Reasons.add(id: id, host: canonical)
        fputs("Touch ID dialog is the approval. Terminal text is not.\n\(reason)\n", stderr)
        fputs("Binary: \(CommandLine.arguments[0])\n", stderr)
        try Fingerprint.require(reason: reason)
        let secret = try readSecretFromTTY()
        defer { zero(secret) }
        try KeychainStore.addSecret(id: id, host: canonical, secret: secret)
        var catalog = try CatalogStore.load()
        catalog.keys.removeAll { $0.id == id }
        catalog.keys.append(CatalogEntry(id: id, description: description, aliases: aliases, mapsTo: mapsTo, host: canonical))
        catalog.keys.sort { $0.id < $1.id }
        try CatalogStore.save(catalog)
        print("saved \(id)")
    }

    static func runCommand(_ args: [String]) throws {
        guard let split = args.firstIndex(of: "--"), split > 0, split + 1 < args.count else {
            throw CLIError.message("usage: keylock run <id> -- <command> [args...]")
        }
        let id = args[0]
        try KeyID.validate(id)
        let command = Array(args[(split + 1)...])
        guard !command.isEmpty else { throw CLIError.message("missing command after --") }
        let executable = try resolveExecutable(command[0])
        let digest = try sha256File(executable)
        let prefix = String(digest.prefix(12))
        let host = try KeychainStore.loadHost(id: id)
        let allowed = try KeychainStore.loadAllowlist()
        guard allowed.contains(host) else {
            throw CLIError.message("\(host) is not on the host list")
        }
        let reason = try Reasons.run(id: id, host: host, sha256Prefix: prefix)
        let auth = try KeychainStore.loadAuth()
        let now = Date()
        fputs("Touch ID dialog is the approval. Terminal text is not.\n", stderr)
        fputs("\(reason)\nexe=\(executable)\nsha256=\(digest)\n", stderr)
        fputs("auth: \(AuthPolicy.describe(auth, now: now))\n", stderr)
        fputs("Any local process can use the proxy until this command exits. The named command is not a boundary.\n", stderr)
        let before = try fileIdentity(executable)
        if AuthPolicy.needsFingerprint(auth, now: now) {
            try Fingerprint.require(reason: reason)
            if case .interval = auth.mode {
                try KeychainStore.saveAuth(AuthPolicy.unlocked(after: Date(), mode: auth.mode))
            }
        }
        let after = try fileIdentity(executable)
        guard before == after else {
            throw CLIError.message("executable changed after the dialog; refusing to run it")
        }
        let fresh = try KeychainStore.loadSecret(id: id)
        defer { zero(fresh.secret) }
        guard fresh.host == host else {
            throw CLIError.message("key host changed after the dialog; refusing")
        }
        let proxy = try LocalProxy(host: host, secret: fresh.secret)
        proxy.start()
        defer { proxy.stop() }
        let base = "http://127.0.0.1:\(proxy.port)"
        var environment = ProcessInfo.processInfo.environment
        for name in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy", "CURL_HOME", "SSLKEYLOGFILE", "CFNETWORK_DIAGNOSTICS"] {
            environment.removeValue(forKey: name)
        }
        environment["KEYLOCK_BASE_URL"] = base
        if host == "api.openai.com" || host == "api.x.ai" {
            environment["OPENAI_BASE_URL"] = base + "/v1"
        }
        if host == "api.x.ai" {
            environment["XAI_BASE_URL"] = base + "/v1"
        }
        if host == "api.anthropic.com" {
            environment["ANTHROPIC_BASE_URL"] = base
        }
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        environment.removeValue(forKey: "XAI_API_KEY")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
    }

    static func auth(_ args: [String]) throws {
        if args.isEmpty {
            let state = try KeychainStore.loadAuth()
            print(AuthPolicy.describe(state))
            return
        }
        guard args.count == 1 else {
            throw CLIError.message("usage: keylock auth [always|never|30m|1h|3h|1d]")
        }
        let mode = try AuthPolicy.parse(args[0])
        let next = AuthPolicy.unlocked(after: Date(), mode: mode)
        let reason = "AUTH mode=\(AuthPolicy.describe(next))"
        fputs("Touch ID dialog is the approval. Terminal text is not.\n\(reason)\n", stderr)
        try Fingerprint.require(reason: reason)
        try KeychainStore.saveAuth(next)
        print(AuthPolicy.describe(next))
    }

    static func doctor() throws {
        let path = CommandLine.arguments[0]
        print("binary: \(path)")
        print("catalog: \(CatalogStore.fileURL.path)")
        print("fingerprint: required by this tool before it reads a key")
        print("platform: other programs can still raise a Keychain Allow dialog. That dialog is not Touch ID. See PLATFORM.md")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=2", path]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print(text)
        if !text.contains("runtime") {
            fputs("warning: hardened runtime flag was not seen in codesign output\n", stderr)
        }
    }

    static func resolveExecutable(_ name: String) throws -> String {
        if name.contains("/") {
            let path = URL(fileURLWithPath: name).standardizedFileURL.path
            guard FileManager.default.isExecutableFile(atPath: path) else {
                throw CLIError.message("not executable: \(path)")
            }
            return path
        }
        let search = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for directory in search.split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw CLIError.message("command not found: \(name)")
    }

    static func sha256File(_ path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileIdentity(_ path: String) throws -> (UInt64, UInt64) {
        let values = try FileManager.default.attributesOfItem(atPath: path)
        let inode = (values[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (values[.size] as? NSNumber)?.uint64Value ?? 0
        return (inode, size)
    }

    static func readSecretFromTTY() throws -> Data {
        guard let tty = fopen("/dev/tty", "r+") else {
            throw CLIError.message("add must be run from a terminal, not a pipe")
        }
        defer { fclose(tty) }
        var original = termios()
        tcgetattr(fileno(tty), &original)
        var hidden = original
        hidden.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(fileno(tty), TCSANOW, &hidden)
        defer { tcsetattr(fileno(tty), TCSANOW, &original) }
        fputs("Secret (not echoed): ", stderr)
        fflush(stderr)
        var buffer = [Int8](repeating: 0, count: 4096)
        guard fgets(&buffer, Int32(buffer.count), tty) != nil else {
            throw CLIError.message("could not read secret")
        }
        fputs("\n", stderr)
        let text = String(cString: buffer).trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { throw CLIError.message("empty secret") }
        return Data(text.utf8)
    }

    static func zero(_ data: Data) {
        var copy = data
        copy.resetBytes(in: 0..<copy.count)
    }

    static func clearProxyEnvironment() {
        for name in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy", "CURL_HOME", "SSLKEYLOGFILE", "CFNETWORK_DIAGNOSTICS"] {
            unsetenv(name)
        }
    }

    static func setrlimitCoreZero() {
        var limit = rlimit(rlim_cur: 0, rlim_max: 0)
        setrlimit(RLIMIT_CORE, &limit)
    }
}

