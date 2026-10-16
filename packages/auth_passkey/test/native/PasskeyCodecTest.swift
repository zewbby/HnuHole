import Foundation

@main
struct PasskeyCodecTest {
    static func encoded(_ count: Int, _ value: UInt8 = 7) -> String { PasskeyCodec.encoded(Data(repeating: value, count: count)) }
    static func json(_ value: [String: Any]) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)! }
    static func get() -> [String: Any] { ["challenge": encoded(32), "rpId": "auth.example.invalid", "timeout": 60000, "userVerification": "required"] }
    static func create() -> [String: Any] {
        ["challenge": encoded(32), "timeout": 60000, "rp": ["id": "auth.example.invalid", "name": "Hnuhole"],
         "user": ["id": encoded(32, 9), "name": encoded(32, 9), "displayName": "Hnuhole account"],
         "pubKeyCredParams": [["type": "public-key", "alg": -7]], "excludeCredentials": [[String: String]](),
         "authenticatorSelection": ["residentKey": "required", "requireResidentKey": true, "userVerification": "required"], "attestation": "none"]
    }
    static func rejects(_ label: String, _ action: () throws -> Void) {
        do { try action(); fatalError("Expected rejection: \(label)") } catch { }
    }
    static func main() throws {
        let input = create()
        let options = try PasskeyCodec.options(json(input), create: true)
        precondition(options.challenge == Data(repeating: 7, count: 32))
        precondition(options.userID == Data(repeating: 9, count: 32))
        var override = input; override["origin"] = "https://auth.example.invalid"
        rejects("origin override") { _ = try PasskeyCodec.options(json(override), create: true) }
        var weak = input; weak["attestation"] = "direct"
        rejects("attestation") { _ = try PasskeyCodec.options(json(weak), create: true) }
        var weakUV = input; weakUV["authenticatorSelection"] = ["residentKey": "required", "requireResidentKey": true, "userVerification": "preferred"]
        rejects("UV") { _ = try PasskeyCodec.options(json(weakUV), create: true) }
        var username = input; username["user"] = ["id": encoded(32, 9), "name": "private_username", "displayName": "Hnuhole account"]
        rejects("private username") { _ = try PasskeyCodec.options(json(username), create: true) }
        let discovery = try PasskeyCodec.options(json(get()), create: false)
        precondition(discovery.userID == nil && discovery.excludes.isEmpty)
        var named = get(); named["allowCredentials"] = [String]()
        rejects("allow list") { _ = try PasskeyCodec.options(json(named), create: false) }
        var newline = get(); newline["rpId"] = "auth.example.invalid\n"
        rejects("RP newline") { _ = try PasskeyCodec.options(json(newline), create: false) }
        var padded = get(); padded["challenge"] = encoded(32) + "="
        rejects("padded challenge") { _ = try PasskeyCodec.options(json(padded), create: false) }
        var numericBool = input; numericBool["authenticatorSelection"] = ["residentKey": "required", "requireResidentKey": 1, "userVerification": "required"]
        rejects("numeric bool") { _ = try PasskeyCodec.options(json(numericBool), create: true) }
        var booleanTimeout = get(); booleanTimeout["timeout"] = true
        rejects("boolean timeout") { _ = try PasskeyCodec.options(json(booleanTimeout), create: false) }
        let client = Data("{\"origin\":\"https://auth.example.invalid\",\"challenge\":\"unmodified\"}".utf8)
        let assertion = try PasskeyCodec.assertion(id: Data(repeating: 7, count: 16), clientData: client,
            authenticatorData: Data(repeating: 7, count: 37), signature: Data(repeating: 7, count: 72), userID: Data(repeating: 9, count: 32))
        let result = try JSONSerialization.jsonObject(with: Data(assertion.utf8)) as! [String: Any]
        let response = result["response"] as! [String: String]
        precondition(response["clientDataJSON"] == PasskeyCodec.encoded(client))
        precondition(Set(result.keys) == ["id", "rawId", "type", "response", "clientExtensionResults"])
        precondition((result["clientExtensionResults"] as! [String: Any]).isEmpty)
        rejects("missing discoverable user") {
            _ = try PasskeyCodec.assertion(id: Data([7]), clientData: client, authenticatorData: Data(repeating: 7, count: 37),
                signature: Data(repeating: 7, count: 72), userID: Data())
        }
        rejects("oversized client data") {
            _ = try PasskeyCodec.registration(id: Data([7]), clientData: Data(repeating: 7, count: 3073), attestation: Data([7]))
        }
        let pending = PendingOperation<NSObject>()
        let first = NSObject(), second = NSObject()
        precondition(pending.begin(first) && !pending.begin(second))
        precondition(pending.cancel() === first && pending.begin(second))
        precondition(pending.take(first) == nil && pending.take(second) === second)
        precondition(pending.take(second) == nil && pending.cancel() == nil)
        print("Passkey codec and cancellation ownership checks passed (no iOS platform operation)")
    }
}
