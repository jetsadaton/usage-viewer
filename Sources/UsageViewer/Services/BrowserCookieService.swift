import Foundation
import Security
import CommonCrypto

// Extracts Claude sessionKey from Chromium-based browsers (Chrome, Arc, Brave)
// Same approach as ControlTower: Keychain master key → PBKDF2 → AES-128-CBC decrypt
enum BrowserCookieService {

    private struct Browser {
        let keychainService: String
        let dbPath: String
        var keychainAccount: String? = nil  // nil = use default (same as service name)
    }

    private static let browsers: [Browser] = [
        // Claude Desktop (Electron) — uses "Claude Key" account instead of default
        Browser(keychainService: "Claude Safe Storage",
                dbPath: "~/Library/Application Support/Claude/Cookies",
                keychainAccount: "Claude Key"),
        Browser(keychainService: "Chrome Safe Storage",
                dbPath: "~/Library/Application Support/Google/Chrome/Default/Cookies"),
        Browser(keychainService: "Arc Safe Storage",
                dbPath: "~/Library/Application Support/Arc/User Data/Default/Cookies"),
        Browser(keychainService: "Brave Safe Storage",
                dbPath: "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies"),
        Browser(keychainService: "Chromium Keys",
                dbPath: "~/Library/Application Support/Chromium/Default/Cookies"),
        Browser(keychainService: "Microsoft Edge Safe Storage",
                dbPath: "~/Library/Application Support/Microsoft Edge/Default/Cookies"),
    ]

    static func claudeSessionKey() -> String? {
        for browser in browsers {
            guard let key = derivedKey(service: browser.keychainService, account: browser.keychainAccount) else { continue }
            if let cookie = extractCookie(from: browser.dbPath, key: key) {
                return cookie
            }
        }
        return nil
    }

    // MARK: - PBKDF2 key derivation

    private static func derivedKey(service: String, account: String?) -> Data? {
        // Read browser's master encryption password from macOS Keychain
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount] = account }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else { return nil }

        // Derive 16-byte AES key via PBKDF2-SHA1
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array("saltysalt".utf8)
        var derivedKey = [UInt8](repeating: 0, count: 16)

        let status: Int32 = passwordBytes.withUnsafeBytes { pwdPtr in
            saltBytes.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwdPtr.bindMemory(to: Int8.self).baseAddress,
                    passwordBytes.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    &derivedKey,
                    derivedKey.count
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(derivedKey)
    }

    // MARK: - Cookie extraction

    private static func extractCookie(from dbPath: String, key: Data) -> String? {
        let expanded = (dbPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }

        // Copy DB to temp — Chrome locks it while running
        let tempDB = NSTemporaryDirectory() + "uv_cookies_\(ProcessInfo.processInfo.processIdentifier).db"
        let tempWAL = tempDB + "-wal"
        try? FileManager.default.removeItem(atPath: tempDB)
        guard (try? FileManager.default.copyItem(atPath: expanded, toPath: tempDB)) != nil else { return nil }
        if FileManager.default.fileExists(atPath: expanded + "-wal") {
            try? FileManager.default.copyItem(atPath: expanded + "-wal", toPath: tempWAL)
        }
        defer {
            try? FileManager.default.removeItem(atPath: tempDB)
            try? FileManager.default.removeItem(atPath: tempWAL)
        }

        // HEX() lets us read binary BLOB as a hex string via sqlite3 CLI
        let sql = "SELECT HEX(encrypted_value) FROM cookies WHERE host_key LIKE '%claude.ai%' AND name='sessionKey' LIMIT 1;"
        guard let hexStr = runSQLite(db: tempDB, query: sql),
              !hexStr.isEmpty,
              let encryptedData = Data(hexString: hexStr) else { return nil }

        return decryptChromeCookie(encryptedData, key: key)
    }

    // MARK: - AES-128-CBC decrypt

    private static func decryptChromeCookie(_ data: Data, key: Data) -> String? {
        // Chrome format: "v10" (3 bytes) + AES-128-CBC ciphertext
        // IV = 16 × 0x20 (space) — first 32 decrypted bytes are Chrome internal metadata,
        // the actual cookie value starts at the "sk-ant" marker.
        guard data.count > 3,
              let prefix = String(data: data.prefix(3), encoding: .utf8),
              prefix == "v10" || prefix == "v11" else { return nil }

        let ciphertext = [UInt8](data.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        let keyBytes = [UInt8](key)

        var plaintext = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var plaintextLen = 0

        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes, keyBytes.count,
            iv,
            ciphertext, ciphertext.count,
            &plaintext, plaintext.count,
            &plaintextLen
        )
        guard status == kCCSuccess else { return nil }

        let decrypted = Array(plaintext.prefix(plaintextLen))

        // The AES decryption leaves Chrome metadata in the first 32 bytes.
        // Find the actual cookie value by scanning for known prefixes.
        let prefixes: [[UInt8]] = [
            Array("sk-ant".utf8),  // Claude session key
        ]
        for marker in prefixes {
            for i in 0...(decrypted.count - marker.count) {
                if Array(decrypted[i..<i + marker.count]) == marker {
                    return String(bytes: decrypted[i...], encoding: .utf8)
                }
            }
        }
        // Fallback: try direct UTF-8 decode
        return String(bytes: decrypted, encoding: .utf8)
    }

    // MARK: - SQLite helper

    private static func runSQLite(db: String, query: String) -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [db, query]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Hex string → Data

private extension Data {
    init?(hexString: String) {
        let s = hexString.uppercased()
        guard s.count % 2 == 0 else { return nil }
        var data = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let byte = UInt8(s[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        self = data
    }
}
