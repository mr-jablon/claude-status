import ClaudeStatusCore
import Foundation

/// Reads the token through `/usr/bin/security`: the Keychain item's ACL trusts that tool,
/// so there is no access prompt, unlike `SecItemCopyMatching` from an ad-hoc signed app.
struct SecurityCLITokenProvider: TokenProviding {
    enum Failure: Error { case itemNotFound(status: Int32) }

    func readToken() async throws -> OAuthToken {
        try await Task.detached(priority: .utility) { try Self.read() }.value
    }

    private static func read() throws -> OAuthToken {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.itemNotFound(status: process.terminationStatus) }
        return try OAuthToken.parse(keychainJSON: data)
    }
}
