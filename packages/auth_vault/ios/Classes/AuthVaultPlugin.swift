import Flutter
import Foundation
import Security
import Darwin

public class AuthVaultPlugin: NSObject, FlutterPlugin {
    private let queue = DispatchQueue(label: "hnuhole.auth.vault")
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "hnuhole/auth_vault", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(AuthVaultPlugin(), channel: channel)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "read" || call.method == "write" else { result(FlutterMethodNotImplemented); return }
        queue.async {
            do {
                guard let arguments = call.arguments as? [String: Any], let namespace = arguments["namespace"] as? String,
                      namespace.range(of: "^[A-Za-z0-9_.-]{1,128}$", options: .regularExpression) != nil else { throw VaultError.unavailable }
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: namespace, kSecAttrAccount as String: "state",
                    kSecAttrSynchronizable as String: false]
                try self.ensureInstallation(namespace, query: query)
                if call.method == "read" {
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
                    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                    if status == errSecItemNotFound {
                        status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
                    }
                    guard status == errSecSuccess else { throw VaultError.unavailable }
                    DispatchQueue.main.async { result(nil) }
                }
            } catch {
                DispatchQueue.main.async { result(FlutterError(code: "AUTH_STORAGE_UNAVAILABLE", message: "Authentication storage unavailable", details: nil)) }
            }
        }
    }
    // Keychain can survive uninstall. A non-secret, backup-excluded app marker
    // makes reinstall a new installation instead of silently restoring it.
    private func ensureInstallation(_ namespace: String, query: [String: Any]) throws {
        let manager = FileManager.default
        var directory = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true).appendingPathComponent("AuthInstallation", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var exclusion = URLResourceValues()
        exclusion.isExcludedFromBackup = true
        try directory.setResourceValues(exclusion)
        var marker = directory.appendingPathComponent(namespace + ".installed")
        if manager.fileExists(atPath: marker.path) {
            guard try Data(contentsOf: marker) == Data([1]) else { throw VaultError.unavailable }
            return
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.unavailable }
        try Data([1]).write(to: marker, options: .atomic)
        try marker.setResourceValues(exclusion)
        try synchronize(marker.path)
        try synchronize(directory.path)
        try synchronize(directory.deletingLastPathComponent().path)
        try synchronize(directory.deletingLastPathComponent().deletingLastPathComponent().path)
    }
    private func synchronize(_ path: String) throws {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { throw VaultError.unavailable }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw VaultError.unavailable }
    }
    private enum VaultError: Error { case unavailable }
}
