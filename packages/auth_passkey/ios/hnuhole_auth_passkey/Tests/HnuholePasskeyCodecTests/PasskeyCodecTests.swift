import Foundation
import XCTest
@testable import hnuhole_auth_passkey

final class PasskeyCodecTests: XCTestCase {
    private func encoded(_ count: Int) -> String { PasskeyCodec.encoded(Data(repeating: 7, count: count)) }
    private func json(_ value: [String: Any]) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
    private func get() -> [String: Any] { ["challenge": encoded(32), "rpId": "auth.example.invalid", "timeout": 60000, "userVerification": "required"] }
    func testDiscoverableRecoveryDecodesOriginalChallengeWithoutAllowList() throws {
        let options = try PasskeyCodec.options(json(get()), create: false)
        XCTAssertEqual(options.challenge, Data(repeating: 7, count: 32))
        XCTAssertNil(options.userID)
        var named = get(); named["allowCredentials"] = [String]()
        XCTAssertThrowsError(try PasskeyCodec.options(json(named), create: false))
        var override = get(); override["clientDataHash"] = encoded(32)
        XCTAssertThrowsError(try PasskeyCodec.options(json(override), create: false))
    }
    func testSignatureAndClientDataBytesArePreservedWithExactResponseFields() throws {
        let client = Data("{\"origin\":\"https://auth.example.invalid\"}".utf8)
        let raw = try PasskeyCodec.assertion(id: Data([7]), clientData: client,
            authenticatorData: Data(repeating: 7, count: 37), signature: Data(repeating: 8, count: 72), userID: Data(repeating: 9, count: 32))
        let response = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        XCTAssertEqual(Set(response.keys), ["id", "rawId", "type", "response", "clientExtensionResults"])
        XCTAssertEqual((response["response"] as! [String: String])["clientDataJSON"], PasskeyCodec.encoded(client))
        XCTAssertEqual((response["response"] as! [String: String])["signature"], PasskeyCodec.encoded(Data(repeating: 8, count: 72)))
    }
    func testMissingUserHandleAndOversizedAttestationAreRejected() throws {
        XCTAssertThrowsError(try PasskeyCodec.assertion(id: Data([7]), clientData: Data([7]),
            authenticatorData: Data(repeating: 7, count: 37), signature: Data(repeating: 7, count: 72), userID: Data()))
        XCTAssertThrowsError(try PasskeyCodec.registration(id: Data([7]), clientData: Data([7]), attestation: Data(repeating: 7, count: 4097)))
    }
    func testCancelledProviderCallbackCannotCompleteANewerOperation() {
        let pending = PendingOperation<NSObject>()
        let first = NSObject(), second = NSObject()
        XCTAssertTrue(pending.begin(first))
        XCTAssertFalse(pending.begin(second))
        XCTAssertTrue(pending.cancel() === first)
        XCTAssertTrue(pending.begin(second))
        XCTAssertNil(pending.take(first))
        XCTAssertTrue(pending.take(second) === second)
        XCTAssertNil(pending.take(second))
    }
}
