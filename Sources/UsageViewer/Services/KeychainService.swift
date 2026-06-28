import Foundation

// ponytail: file storage instead of Keychain — avoids unsigned-app access prompts
enum KeychainService {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/usage-viewer")
    private static let configFile = configDir.appendingPathComponent("credentials.json")

    static func saveClaudeKey(_ key: String) throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(["claudeSessionKey": key])
        try data.write(to: configFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
    }

    static func loadClaudeKey() -> String? {
        guard let data = try? Data(contentsOf: configFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return dict["claudeSessionKey"]
    }
}
