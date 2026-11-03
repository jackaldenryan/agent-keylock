import XCTest
@testable import KeylockCore

final class KeylockCoreTests: XCTestCase {
    func testRejectsLookalikeLetters() {
        XCTAssertThrowsError(try HostGrammar.canonicalize("аpi.openai.com")) { error in
            XCTAssertEqual(error as? HostGrammarError, .notASCII)
        }
    }

    func testRejectsPunycodeAndURLSyntax() {
        XCTAssertThrowsError(try HostGrammar.canonicalize("xn--pple-43d.com"))
        XCTAssertThrowsError(try HostGrammar.canonicalize("https://api.openai.com/v1"))
        XCTAssertNoThrow(try HostGrammar.canonicalize("api.openai.com.evil.example"))
        XCTAssertThrowsError(try HostGrammar.canonicalize("user@api.openai.com"))
        XCTAssertThrowsError(try HostGrammar.canonicalize("api.openai.com."))
        XCTAssertThrowsError(try HostGrammar.canonicalize("localhost"))
    }

    func testAcceptsVendorHostAndShowsItInFull() throws {
        let host = try HostGrammar.canonicalize("API.OpenAI.com")
        XCTAssertEqual(host, "api.openai.com")
        let reason = try Reasons.allowHost("api.openai.com")
        XCTAssertEqual(reason, "ALLOW-HOST host=api.openai.com port=443 match=exact")
        XCTAssertLessThanOrEqual(reason.count, HostGrammar.maxDialogReasonLength)
        XCTAssertFalse(reason.contains("…"))
    }

    func testRunReasonNamesTheWiderProxyScope() throws {
        let reason = try Reasons.run(id: "openai-personal", host: "api.openai.com", sha256Prefix: "0123456789ab")
        XCTAssertTrue(reason.hasPrefix("RUN "))
        XCTAssertTrue(reason.contains("any-local-until-exit"))
        XCTAssertTrue(reason.contains("key=openai-personal"))
    }

    func testRedactsRawAndEncodedSecret() {
        let secret = Data("sk-test-secret".utf8)
        XCTAssertTrue(Redact.containsSecret(Data("prefix sk-test-secret suffix".utf8), secret: secret))
        XCTAssertTrue(Redact.containsSecret(secret.base64EncodedData(), secret: secret))
        XCTAssertFalse(Redact.containsSecret(Data("no secret here".utf8), secret: secret))
    }

    func testCatalogReferenceHasNoSecret() throws {
        let entry = CatalogEntry(id: "openai-personal", description: "personal", aliases: ["openai"], mapsTo: "OPENAI_API_KEY", host: "api.openai.com")
        let data = try JSONEncoder().encode(entry)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(entry.reference, "keylock://openai-personal")
        XCTAssertFalse(text.contains("sk-"))
        XCTAssertFalse(text.contains("secret"))
    }

    func testAuthModes() throws {
        XCTAssertEqual(try AuthPolicy.parse("always"), .always)
        XCTAssertEqual(try AuthPolicy.parse("off"), .never)
        XCTAssertEqual(try AuthPolicy.parse("3h"), .interval(seconds: 3 * 60 * 60))
        XCTAssertEqual(try AuthPolicy.parse("1d"), .interval(seconds: 24 * 60 * 60))
        XCTAssertThrowsError(try AuthPolicy.parse("sometimes"))

        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(AuthPolicy.needsFingerprint(.default, now: now))
        XCTAssertFalse(AuthPolicy.needsFingerprint(AuthState(mode: .never), now: now))
        let open = AuthState(mode: .interval(seconds: 3600), unlockedUntil: now.addingTimeInterval(10))
        XCTAssertFalse(AuthPolicy.needsFingerprint(open, now: now))
        let expired = AuthState(mode: .interval(seconds: 3600), unlockedUntil: now.addingTimeInterval(-1))
        XCTAssertTrue(AuthPolicy.needsFingerprint(expired, now: now))

        let encoded = AuthPolicy.encode(open)
        XCTAssertEqual(AuthPolicy.decode(encoded).mode, open.mode)
        XCTAssertEqual(
            AuthPolicy.decode(encoded).unlockedUntil?.timeIntervalSince1970,
            open.unlockedUntil?.timeIntervalSince1970
        )
    }

    func testRejectsBadKeyID() {
        XCTAssertThrowsError(try KeyID.validate("OpenAI"))
        XCTAssertThrowsError(try KeyID.validate("../x"))
        XCTAssertNoThrow(try KeyID.validate("openai-personal"))
    }
}
