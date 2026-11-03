import Foundation

public enum Reasons {
    public static func add(id: String, host: String) throws -> String {
        try KeyID.validate(id)
        let host = try HostGrammar.canonicalize(host)
        let reason = "ADD key=\(id) host=\(host)"
        try fit(reason)
        return reason
    }

    public static func allowHost(_ host: String) throws -> String {
        let host = try HostGrammar.canonicalize(host)
        let reason = HostGrammar.allowHostReason(host)
        try fit(reason)
        return reason
    }

    public static func revokeHost(_ host: String) throws -> String {
        let host = try HostGrammar.canonicalize(host)
        let reason = "REVOKE-HOST host=\(host)"
        try fit(reason)
        return reason
    }

    public static func run(id: String, host: String, sha256Prefix: String) throws -> String {
        try KeyID.validate(id)
        let host = try HostGrammar.canonicalize(host)
        let reason = "RUN key=\(id) host=\(host) sha=\(sha256Prefix) any-local-until-exit"
        try fit(reason)
        return reason
    }

    static func fit(_ reason: String) throws {
        guard reason.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else {
            throw ReasonError.notASCII
        }
        guard reason.count <= HostGrammar.maxDialogReasonLength else {
            throw ReasonError.tooLong
        }
    }
}

public enum ReasonError: Error, Equatable, CustomStringConvertible {
    case notASCII
    case tooLong
    public var description: String {
        switch self {
        case .notASCII: "approval text must be plain ASCII"
        case .tooLong: "approval text would be clipped in the Touch ID dialog"
        }
    }
}
