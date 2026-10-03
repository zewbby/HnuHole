import Foundation
import CoreFoundation

enum PasskeyCodec {
    enum Invalid: Error { case value }
    struct Options {
        let rpID: String
        let challenge: Data
        let userID: Data?
        let userName: String?
        let excludes: [Data]
    }

    static func options(_ raw: String, create: Bool) throws -> Options {
        guard let data = raw.data(using: .utf8), data.count <= 32768,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Invalid.value }
        try keys(value, create ? ["challenge", "rp", "user", "pubKeyCredParams", "timeout", "excludeCredentials", "authenticatorSelection", "attestation"] :
            ["challenge", "rpId", "timeout", "userVerification"])
        let challenge = try decoded(value["challenge"], minimum: 32, maximum: 32)
        try integer(value["timeout"], expected: 60000)
        if !create {
            let rpID = try relyingParty(value["rpId"])
            guard value["userVerification"] as? String == "required" else { throw Invalid.value }
            return Options(rpID: rpID, challenge: challenge, userID: nil, userName: nil, excludes: [])
        }
        guard let rp = value["rp"] as? [String: Any], let user = value["user"] as? [String: Any],
              let selection = value["authenticatorSelection"] as? [String: Any],
              let algorithms = value["pubKeyCredParams"] as? [[String: Any]], algorithms.count == 1,
              let exclude = value["excludeCredentials"] as? [[String: Any]], exclude.count <= 10 else { throw Invalid.value }
        try keys(rp, ["id", "name"])
        try keys(user, ["id", "name", "displayName"])
        try keys(selection, ["residentKey", "requireResidentKey", "userVerification"])
        try keys(algorithms[0], ["type", "alg"])
        try integer(algorithms[0]["alg"], expected: -7)
        let rpID = try relyingParty(rp["id"])
        let userID = try decoded(user["id"], minimum: 32, maximum: 32)
        guard let userName = user["name"] as? String, userName == user["id"] as? String,
              rp["name"] as? String == "Hnuhole", user["displayName"] as? String == "Hnuhole account",
              algorithms[0]["type"] as? String == "public-key", selection["residentKey"] as? String == "required",
              selection["userVerification"] as? String == "required", value["attestation"] as? String == "none",
              let resident = selection["requireResidentKey"] as? NSNumber,
              CFGetTypeID(resident) == CFBooleanGetTypeID(), resident.boolValue else { throw Invalid.value }
        var seen = Set<Data>()
        var excludes = [Data]()
        for item in exclude {
            try keys(item, ["id", "type"])
            let id = try decoded(item["id"], minimum: 1, maximum: 1023)
            guard item["type"] as? String == "public-key", seen.insert(id).inserted else { throw Invalid.value }
            excludes.append(id)
        }
        return Options(rpID: rpID, challenge: challenge, userID: userID, userName: userName, excludes: excludes)
    }

    static func registration(id: Data, clientData: Data, attestation: Data) throws -> String {
        try bounded(id, minimum: 1, maximum: 1023)
        try bounded(clientData, minimum: 1, maximum: 3072)
        try bounded(attestation, minimum: 1, maximum: 4096)
        return try response(id: id, fields: ["clientDataJSON": encoded(clientData), "attestationObject": encoded(attestation)])
    }
    static func assertion(id: Data, clientData: Data, authenticatorData: Data, signature: Data, userID: Data) throws -> String {
        try bounded(id, minimum: 1, maximum: 1023)
        try bounded(clientData, minimum: 1, maximum: 3072)
        try bounded(authenticatorData, minimum: 37, maximum: 2048)
        try bounded(signature, minimum: 8, maximum: 1024)
        try bounded(userID, minimum: 32, maximum: 32)
        return try response(id: id, fields: ["clientDataJSON": encoded(clientData), "authenticatorData": encoded(authenticatorData),
            "signature": encoded(signature), "userHandle": encoded(userID)])
    }
    static func encoded(_ value: Data) -> String {
        value.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func response(id: Data, fields: [String: String]) throws -> String {
        let value: [String: Any] = ["id": encoded(id), "rawId": encoded(id), "type": "public-key", "response": fields,
            "clientExtensionResults": [String: Any]()]
        let data = try JSONSerialization.data(withJSONObject: value)
        guard data.count <= 32768, let text = String(data: data, encoding: .utf8) else { throw Invalid.value }
        return text
    }
    private static func keys(_ value: [String: Any], _ required: Set<String>) throws {
        guard Set(value.keys) == required else { throw Invalid.value }
    }
    private static func integer(_ value: Any?, expected: Int) throws {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(expected) else { throw Invalid.value }
    }
    private static func relyingParty(_ value: Any?) throws -> String {
        guard let value = value as? String, value.count <= 253,
              value.range(of: "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$", options: .regularExpression) == (value.startIndex..<value.endIndex),
              value.split(separator: ".").allSatisfy({ $0.count <= 63 }),
              value.range(of: "^[0-9.]+$", options: .regularExpression) == nil else { throw Invalid.value }
        return value
    }
    private static func decoded(_ value: Any?, minimum: Int, maximum: Int) throws -> Data {
        guard let value = value as? String, value.count <= (maximum * 4 + 2) / 3,
              value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw Invalid.value }
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), encoded(data) == value else { throw Invalid.value }
        try bounded(data, minimum: minimum, maximum: maximum)
        return data
    }
    private static func bounded(_ value: Data, minimum: Int, maximum: Int) throws {
        guard (minimum...maximum).contains(value.count) else { throw Invalid.value }
    }
}
