import Foundation

public enum Redact {
    public static func containsSecret(_ body: Data, secret: Data) -> Bool {
        if secret.isEmpty { return false }
        if body.range(of: secret) != nil { return true }
        let b64 = secret.base64EncodedData()
        if body.range(of: b64) != nil { return true }
        if let text = String(data: secret, encoding: .utf8) {
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
            if let encodedData = encoded.data(using: .utf8), body.range(of: encodedData) != nil, encoded != text {
                return true
            }
            if let urlEncoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .data(using: .utf8), body.range(of: urlEncoded) != nil {
                return true
            }
        }
        return false
    }
}
