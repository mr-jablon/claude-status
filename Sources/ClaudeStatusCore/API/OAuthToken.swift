import Foundation

public struct OAuthToken: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date

    public init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public enum ParseError: Error { case missingClaudeAiOauth }

    /// Parses the JSON stored by Claude Code in the Keychain item `Claude Code-credentials`.
    /// Only `claudeAiOauth.accessToken` and `expiresAt` (milliseconds since 1970) are read;
    /// everything else in the item belongs to Claude Code.
    public static func parse(keychainJSON data: Data) throws -> OAuthToken {
        struct Item: Decodable {
            struct OAuth: Decodable { let accessToken: String; let expiresAt: Double }
            let claudeAiOauth: OAuth?
        }
        guard let oauth = try JSONDecoder().decode(Item.self, from: data).claudeAiOauth else {
            throw ParseError.missingClaudeAiOauth
        }
        return OAuthToken(accessToken: oauth.accessToken,
                          expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1000))
    }
}
