import Foundation

final class FaultingFileSystem: AuthInstallationFileSystem {
    let actual = SystemAuthInstallationFileSystem()
    var failedPath: String?
    var failWrites = false
    func exists(_ url: URL) -> Bool { actual.exists(url) }
    func createDirectory(_ url: URL) throws { try actual.createDirectory(url) }
    func read(_ url: URL) throws -> Data { try actual.read(url) }
    func writeMarker(_ url: URL) throws {
        if failWrites { throw AuthInstallationFailure.unavailable }
        try actual.writeMarker(url)
    }
    func excludeFromBackup(_ url: URL) throws { try actual.excludeFromBackup(url) }
    func synchronize(_ url: URL) throws {
        if url.path == failedPath { throw AuthInstallationFailure.unavailable }
        try actual.synchronize(url)
    }
}
@main struct InstallationMarkerTests {
    static func require(_ value: Bool, _ label: String) throws {
        if !value { throw TestFailure.failed(label) }
    }
    enum TestFailure: Error { case failed(String) }
    static func expectFailure(_ label: String, _ action: () throws -> Void) throws {
        do { try action() } catch is AuthInstallationFailure { return }
        throw TestFailure.failed(label)
    }
    static func main() {
        do { try run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hnuhole-marker-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Support/AuthInstallation")
        let fs = FaultingFileSystem()
        var removals = 0
        let cleanup = { removals += 1 }
        let marker = directory.appendingPathComponent("test.installed")
        fs.failedPath = marker.path
        try expectFailure("initial durability failure must stop before keychain use") {
            try AuthInstallationMarker.ensure(directory: directory, namespace: "test", fileSystem: fs, removePreviousState: cleanup)
        }
        try require(fs.exists(marker), "fault reproduces marker written with unknown durability")
        try expectFailure("existing marker must retry durability confirmation") {
            try AuthInstallationMarker.ensure(directory: directory, namespace: "test", fileSystem: fs, removePreviousState: cleanup)
        }
        fs.failedPath = nil
        try AuthInstallationMarker.ensure(directory: directory, namespace: "test", fileSystem: fs, removePreviousState: cleanup)
        try require(removals == 1, "retry must retain this installation's state")
        fs.failedPath = directory.path
        try expectFailure("directory durability is required on retry") {
            try AuthInstallationMarker.ensure(directory: directory, namespace: "test", fileSystem: fs, removePreviousState: cleanup)
        }
        fs.failedPath = nil
        try Data([2]).write(to: marker, options: .atomic)
        try expectFailure("corrupt marker cannot become a new installation silently") {
            try AuthInstallationMarker.ensure(directory: directory, namespace: "test", fileSystem: fs, removePreviousState: cleanup)
        }
        try require(removals == 1, "corrupt marker cannot erase secure state")
        try FileManager.default.removeItem(at: marker)
        try AuthInstallationMarker.ensure(directory: directory, namespace: "test", fileSystem: fs, removePreviousState: cleanup)
        try require(removals == 2, "missing installation marker must clear previous keychain state")
        print("PASS: marker retry, directory sync, corruption and reinstall")
    }
}
