import Foundation

public enum HostGrammarError: Error, Equatable, CustomStringConvertible {
    case empty
    case notASCII
    case rejectedSyntax
    case tooLongForDialog
    case confusableVendor

    public var description: String {
        switch self {
        case .empty: "host is empty"
        case .notASCII: "host must be plain ASCII; lookalike letters are rejected"
        case .rejectedSyntax: "host must be a bare lowercase hostname, with a dot, and no URL syntax"
        case .tooLongForDialog: "host is too long to show in full in the Touch ID dialog"
        case .confusableVendor: "host is a lookalike of a known vendor host"
        }
    }
}

public enum HostGrammar {
    public static let maxDialogReasonLength = 120
    public static let seededVendors = [
        "api.openai.com",
        "api.x.ai",
        "api.anthropic.com",
        "generativelanguage.googleapis.com",
    ]

    public static func canonicalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HostGrammarError.empty }
        guard trimmed.utf8.allSatisfy({ $0 < 128 }) else { throw HostGrammarError.notASCII }
        let host = trimmed.lowercased()
        guard isBareHostname(host) else { throw HostGrammarError.rejectedSyntax }
        guard !isConfusableVendor(host) else { throw HostGrammarError.confusableVendor }
        let reason = allowHostReason(host)
        guard reason.count <= maxDialogReasonLength else { throw HostGrammarError.tooLongForDialog }
        return host
    }

    public static func allowHostReason(_ host: String) -> String {
        "ALLOW-HOST host=\(host) port=443 match=exact"
    }

    public static func isBareHostname(_ host: String) -> Bool {
        guard host.count <= 253, host.contains(".") else { return false }
        guard !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        let labelPattern = #"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"#
        guard labels.allSatisfy({ $0.range(of: labelPattern, options: .regularExpression) != nil }) else {
            return false
        }
        if host == "localhost" || host.hasSuffix(".localhost") { return false }
        if labels.contains(where: { $0.hasPrefix("xn--") }) { return false }
        return true
    }

    /// ASCII-only lookalikes. Non-ASCII is already rejected.
    static func isConfusableVendor(_ host: String) -> Bool {
        let folded = host
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "l")
            .replacingOccurrences(of: "rn", with: "m")
        return seededVendors.contains(folded) && !seededVendors.contains(host)
    }
}
