import Flutter
import UIKit
import XCTest
import Security
import hnuhole_auth_vault

class RunnerTests: XCTestCase {

  private func invoke(_ plugin: AuthVaultPlugin, _ method: String,
                      _ arguments: [String: Any]) -> Any? {
    let done = expectation(description: "vault callback")
    var value: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
      value = $0
      done.fulfill()
    }
    wait(for: [done], timeout: 10)
    return value
  }

  private func eraseOwnedTestRecord(_ namespace: String) {
    // Only namespaces allocated by this test are touched.
    precondition(namespace.hasPrefix("native.security.test."))
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: namespace, kSecAttrAccount as String: "state",
      kSecAttrSynchronizable as String: false]
    let status = SecItemDelete(query as CFDictionary)
    XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound)
    if let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first {
      try? FileManager.default.removeItem(at: support.appendingPathComponent("AuthInstallation")
        .appendingPathComponent("\(namespace).installed"))
    }
  }

  func testRealKeychainRoundTripAcrossPluginInstances() {
    let namespace = "native.security.test.\(UUID().uuidString)"
    defer { eraseOwnedTestRecord(namespace) }
    let record = "{\"pendingCredentialChange\":{\"state\":\"UNKNOWN\"}}"
    XCTAssertNil(invoke(AuthVaultPlugin(), "write", ["namespace": namespace, "value": record]))
    XCTAssertEqual(invoke(AuthVaultPlugin(), "read", ["namespace": namespace]) as? String, record)
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: namespace, kSecAttrAccount as String: "state",
      kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var result: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
    let attributes = result as? [String: Any]
    XCTAssertEqual(attributes?[kSecAttrAccessible as String] as? String,
                   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual(attributes?[kSecAttrSynchronizable as String] as? Bool, false)
  }

  func testInvalidAndOversizedWritesDoNotReplaceAcknowledgedState() {
    let namespace = "native.security.test.\(UUID().uuidString)"
    defer { eraseOwnedTestRecord(namespace) }
    let plugin = AuthVaultPlugin()
    XCTAssertNil(invoke(plugin, "write", ["namespace": namespace, "value": "acknowledged"] ))
    XCTAssertTrue(invoke(plugin, "write", ["namespace": namespace,
      "value": String(repeating: "x", count: 65537)]) is FlutterError)
    XCTAssertTrue(invoke(plugin, "read", ["namespace": "../invalid"]) is FlutterError)
    XCTAssertEqual(invoke(plugin, "read", ["namespace": namespace]) as? String, "acknowledged")
  }

  // Two separately launched XCTest app processes; write intentionally retains
  // this test's exact record until read. Terminate the app between launches.
  func testExplicitProcessRestartProbe() throws {
    let env = ProcessInfo.processInfo.environment
    guard let phase = env["AUTH_VAULT_RESTART_PHASE"],
          let namespace = env["AUTH_VAULT_RESTART_NAMESPACE"] else {
      throw XCTSkip("Requires external write/read process restart phases")
    }
    guard namespace.range(of: "^native\\.security\\.test\\.[A-Za-z0-9_-]{1,80}$",
                          options: .regularExpression) != nil,
          phase == "write" || phase == "read" else {
      XCTFail("Invalid explicit test namespace/phase")
      return
    }
    let record = "{\"logout\":\"pending\",\"credentialResult\":\"UNKNOWN\",\"probe\":true}"
    if phase == "write" {
      eraseOwnedTestRecord(namespace)
      XCTAssertNil(invoke(AuthVaultPlugin(), "write", ["namespace": namespace, "value": record]))
    } else {
      defer { eraseOwnedTestRecord(namespace) }
      XCTAssertEqual(invoke(AuthVaultPlugin(), "read", ["namespace": namespace]) as? String, record)
    }
  }

}
