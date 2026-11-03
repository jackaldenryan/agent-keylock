import Foundation
import LocalAuthentication

public enum FingerprintError: Error, CustomStringConvertible {
    case unavailable(String)
    case denied
    case failed(String)

    public var description: String {
        switch self {
        case .unavailable(let message): "Touch ID is not available: \(message)"
        case .denied: "Touch ID was cancelled"
        case .failed(let message): "Touch ID failed: \(message)"
        }
    }
}

private final class ResultBox: @unchecked Sendable {
    var succeeded = false
    var failure: String?
}

public enum Fingerprint {
    /// One fresh biometric check. No password button. A recent unlock does not count.
    public static func require(reason: String) throws {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw FingerprintError.unavailable(error?.localizedDescription ?? "biometry unavailable")
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, evalError in
            box.succeeded = ok
            box.failure = evalError?.localizedDescription
            semaphore.signal()
        }
        semaphore.wait()
        context.invalidate()
        if box.succeeded { return }
        if box.failure == nil || (box.failure?.localizedCaseInsensitiveContains("cancel") ?? false) {
            throw FingerprintError.denied
        }
        throw FingerprintError.failed(box.failure ?? "unknown")
    }
}
