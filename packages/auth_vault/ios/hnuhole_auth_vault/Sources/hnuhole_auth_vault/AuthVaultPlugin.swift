import Flutter
import Foundation
import Security
import Darwin

public class AuthVaultPlugin: NSObject, FlutterPlugin {
    // 在多个 Flutter engine 之间串行化 marker 安装和 Keychain 访问。
    private static let queue = DispatchQueue(label: "hnuhole.auth.vault")
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "hnuhole/auth_vault", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(AuthVaultPlugin(), channel: channel)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let business = ["businessRead", "businessWrite", "businessDatabasePath", "businessPurgeClosedAccount"].contains(call.method)
        guard business || call.method == "read" || call.method == "write" else { result(FlutterMethodNotImplemented); return }
        Self.queue.async {
            do {
                guard let arguments = call.arguments as? [String: Any], let supplied = arguments["namespace"] as? String,
                      supplied.range(of: business ? "^[0-9a-f]{64}$" : "^[A-Za-z0-9_.-]{1,128}$", options: .regularExpression) != nil else { throw VaultError.unavailable }
                // 业务 Keychain service、安装标记和 SQLite 目录独立于认证文档。
                let namespace = business ? "hnuhole.business.v1." + supplied : supplied
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: namespace, kSecAttrAccount as String: "state",
                    kSecAttrSynchronizable as String: false]
                if call.method == "businessPurgeClosedAccount" {
                    try self.purgeBusiness(supplied, query: query)
                    DispatchQueue.main.async { result(nil) }
                    return
                }
                let directory = try self.ensureInstallation(namespace, query: query, business: business)
                if call.method == "businessDatabasePath" {
                    let path = directory.appendingPathComponent(supplied + ".sqlite3").path
                    DispatchQueue.main.async { result(path) }
                } else if call.method == "read" || call.method == "businessRead" {
                    var search = query
                    search[kSecReturnData as String] = true
                    search[kSecMatchLimit as String] = kSecMatchLimitOne
                    var raw: CFTypeRef?
                    let status = SecItemCopyMatching(search as CFDictionary, &raw)
                    if status == errSecItemNotFound { DispatchQueue.main.async { result(nil) }; return }
                    guard status == errSecSuccess, let data = raw as? Data, data.count <= 65536,
                          let text = String(data: data, encoding: .utf8) else { throw VaultError.unavailable }
                    DispatchQueue.main.async { result(text) }
                } else {
                    guard let text = arguments["value"] as? String, let data = text.data(using: .utf8), data.count <= 65536 else { throw VaultError.unavailable }
                    let attributes: [String: Any] = [kSecValueData as String: data,
                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
                    var status: OSStatus
                    if business {
                        // 业务密钥只允许首次建立或相同值重试；不静默轮换已有数据库密钥。
                        var search = query
                        search[kSecReturnData as String] = true
                        search[kSecMatchLimit as String] = kSecMatchLimitOne
                        var existing: CFTypeRef?
                        status = SecItemCopyMatching(search as CFDictionary, &existing)
                        if status == errSecItemNotFound {
                            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
                        } else {
                            guard status == errSecSuccess, let previous = existing as? Data, previous == data else { throw VaultError.unavailable }
                        }
                    } else {
                        status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                        if status == errSecItemNotFound {
                            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
                        }
                    }
                    guard status == errSecSuccess else { throw VaultError.unavailable }
                    DispatchQueue.main.async { result(nil) }
                }
            } catch {
                DispatchQueue.main.async { result(FlutterError(
                    code: business ? "BUSINESS_STORAGE_UNAVAILABLE" : "AUTH_STORAGE_UNAVAILABLE",
                    message: business ? "Business storage unavailable" : "Authentication storage unavailable", details: nil)) }
            }
        }
    }
    private func ensureInstallation(_ namespace: String, query: [String: Any], business: Bool) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true).appendingPathComponent(
                                            business ? "HnuholeBusinessV1" : "AuthInstallation", isDirectory: true)
        if business {
            let scope = String(namespace.dropFirst("hnuhole.business.v1.".count))
            guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent(scope + ".closed").path) else {
                throw VaultError.unavailable
            }
        }
        try AuthInstallationMarker.ensure(directory: directory, namespace: namespace) {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.unavailable }
        }
        return directory
    }
    private func purgeBusiness(_ scope: String, query: [String: Any]) throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("HnuholeBusinessV1", isDirectory: true)
        let io = SystemAuthInstallationFileSystem()
        try io.createDirectory(directory)
        try io.excludeFromBackup(directory)
        let marker = directory.appendingPathComponent(scope + ".closed")
        if !io.exists(marker) { try io.writeMarker(marker) }
        guard try io.read(marker) == Data([1]) else { throw VaultError.unavailable }
        try io.excludeFromBackup(marker)
        try io.synchronize(marker)
        try io.synchronize(directory)
        // 先确认闭号墓碑，再移除该 scope 数据；丢失 Keychain 也可重复清理。
        for suffix in [".sqlite3", ".sqlite3-journal", ".sqlite3-wal", ".sqlite3-shm"] {
            let file = directory.appendingPathComponent(scope + suffix)
            if io.exists(file) { try FileManager.default.removeItem(at: file) }
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.unavailable }
        try io.synchronize(directory)
        try io.synchronize(directory.deletingLastPathComponent())
    }
    private enum VaultError: Error { case unavailable }
}
