import Foundation

public enum AuthMode: Equatable, Sendable {
    case always
    case never
    case interval(seconds: Int)
}

public struct AuthState: Equatable, Sendable {
    public var mode: AuthMode
    public var unlockedUntil: Date?

    public init(mode: AuthMode, unlockedUntil: Date? = nil) {
        self.mode = mode
        self.unlockedUntil = unlockedUntil
    }

    public static let `default` = AuthState(mode: .always)
}

public enum AuthPolicyError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let text):
            return "unknown auth setting \(text). Use always, never, or a duration like 30m, 1h, 3h, 1d."
        }
    }
}

public enum AuthPolicy {
    public static func parse(_ raw: String) throws -> AuthMode {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch text {
        case "always", "every", "on":
            return .always
        case "never", "off":
            return .never
        default:
            guard let seconds = durationSeconds(text), seconds > 0, seconds <= 60 * 60 * 24 * 30 else {
                throw AuthPolicyError.invalid(raw)
            }
            return .interval(seconds: seconds)
        }
    }

    public static func needsFingerprint(_ state: AuthState, now: Date = Date()) -> Bool {
        switch state.mode {
        case .always:
            return true
        case .never:
            return false
        case .interval:
            guard let until = state.unlockedUntil else { return true }
            return now >= until
        }
    }

    public static func unlocked(after now: Date, mode: AuthMode) -> AuthState {
        switch mode {
        case .always:
            return AuthState(mode: .always)
        case .never:
            return AuthState(mode: .never)
        case .interval(let seconds):
            return AuthState(mode: mode, unlockedUntil: now.addingTimeInterval(TimeInterval(seconds)))
        }
    }

    public static func describe(_ state: AuthState, now: Date = Date()) -> String {
        switch state.mode {
        case .always:
            return "always"
        case .never:
            return "never"
        case .interval(let seconds):
            let label = durationLabel(seconds)
            if let until = state.unlockedUntil, until > now {
                let remaining = Int(until.timeIntervalSince(now))
                return "\(label), unlocked for \(durationLabel(remaining))"
            }
            return "\(label), locked"
        }
    }

    public static func encode(_ state: AuthState) -> Data {
        var parts = [String]()
        switch state.mode {
        case .always:
            parts.append("always")
        case .never:
            parts.append("never")
        case .interval(let seconds):
            parts.append("interval")
            parts.append(String(seconds))
        }
        if let until = state.unlockedUntil {
            parts.append(String(Int(until.timeIntervalSince1970)))
        }
        return Data(parts.joined(separator: " ").utf8)
    }

    public static func decode(_ data: Data) -> AuthState {
        let text = String(data: data, encoding: .utf8) ?? ""
        let parts = text.split(separator: " ").map(String.init)
        guard let first = parts.first else { return .default }
        switch first {
        case "always":
            return AuthState(mode: .always)
        case "never":
            return AuthState(mode: .never)
        case "interval":
            guard parts.count >= 2, let seconds = Int(parts[1]), seconds > 0 else { return .default }
            let until = parts.count >= 3 ? Int(parts[2]).map { Date(timeIntervalSince1970: TimeInterval($0)) } : nil
            return AuthState(mode: .interval(seconds: seconds), unlockedUntil: until)
        default:
            return .default
        }
    }

    static func durationSeconds(_ text: String) -> Int? {
        guard text.count >= 2, let value = Int(text.dropLast()) else { return nil }
        switch text.last {
        case "m": return value * 60
        case "h": return value * 60 * 60
        case "d": return value * 60 * 60 * 24
        default: return nil
        }
    }

    static func durationLabel(_ seconds: Int) -> String {
        if seconds % 86_400 == 0 { return "\(seconds / 86_400)d" }
        if seconds % 3_600 == 0 { return "\(seconds / 3_600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}
