import Foundation
import Darwin

internal protocol AuthInstallationFileSystem {
    func exists(_ url: URL) -> Bool
    func createDirectory(_ url: URL) throws
    func read(_ url: URL) throws -> Data
    func writeMarker(_ url: URL) throws
    func excludeFromBackup(_ url: URL) throws
    func synchronize(_ url: URL) throws
}

internal struct SystemAuthInstallationFileSystem: AuthInstallationFileSystem {
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func read(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try file.read(upToCount: 2) ?? Data()
    }
    func writeMarker(_ url: URL) throws { try Data([1]).write(to: url, options: .atomic) }
    func excludeFromBackup(_ url: URL) throws {
        var value = url
        var exclusion = URLResourceValues()
        exclusion.isExcludedFromBackup = true
        try value.setResourceValues(exclusion)
    }
    func synchronize(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw AuthInstallationFailure.unavailable }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw AuthInstallationFailure.unavailable }
    }
}

internal enum AuthInstallationFailure: Error { case unavailable }

// Keychain may survive uninstall. This non-secret, backup-excluded marker
// distinguishes an installation; it must be durable before Keychain access.
internal enum AuthInstallationMarker {
    static func ensure(directory: URL, namespace: String,
                       fileSystem: AuthInstallationFileSystem = SystemAuthInstallationFileSystem(),
                       removePreviousState: () throws -> Void) throws {
        guard namespace.range(of: "^[A-Za-z0-9_.-]{1,128}$", options: .regularExpression) != nil else {
            throw AuthInstallationFailure.unavailable
        }
        try fileSystem.createDirectory(directory)
        try fileSystem.excludeFromBackup(directory)
        let marker = directory.appendingPathComponent(namespace + ".installed")
        if fileSystem.exists(marker) {
            guard try fileSystem.read(marker) == Data([1]) else { throw AuthInstallationFailure.unavailable }
        } else {
            try removePreviousState()
            try fileSystem.writeMarker(marker)
        }
        // A previous write may have produced this file without completing the
        // durable acknowledgment. Reconfirm it before all Keychain access.

        try fileSystem.excludeFromBackup(marker)
        try fileSystem.synchronize(marker)
        try fileSystem.synchronize(directory)
        try fileSystem.synchronize(directory.deletingLastPathComponent())
        try fileSystem.synchronize(directory.deletingLastPathComponent().deletingLastPathComponent())
    }
}
