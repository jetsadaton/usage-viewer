import Foundation

enum CodexService {
    private static let authPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")

    static func isConfigured() -> Bool {
        FileManager.default.fileExists(atPath: authPath.path)
    }

    static func fetch() async throws -> CodexData {
        let auth = try loadAuth()
        return try await fetchUsage(auth: auth)
    }

    private static func loadAuth() throws -> CodexAuth {
        guard isConfigured() else { throw ServiceError.authFileNotFound }
        let data = try Data(contentsOf: authPath)
        return try JSONDecoder().decode(CodexAuth.self, from: data)
    }

    private static func fetchUsage(auth: CodexAuth) async throws -> CodexData {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(auth.tokens.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = auth.tokens.accountId {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await withRetry {
            let (d, r) = try await URLSession.shared.data(for: req)
            guard let http = r as? HTTPURLResponse, http.statusCode == 200 else {
                throw ServiceError.httpError((r as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return (d, r)
        }
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        let primary = decoded.rateLimit?.primaryWindow
        let secondary = decoded.rateLimit?.secondaryWindow
        return CodexData(
            primaryPct: primary?.usedPercent ?? 0,
            secondaryPct: secondary?.usedPercent,
            primaryResetsAt: primary.map { Date(timeIntervalSince1970: TimeInterval($0.resetAt)) },
            secondaryResetsAt: secondary.map { Date(timeIntervalSince1970: TimeInterval($0.resetAt)) },
            limitWindowSeconds: primary?.limitWindowSeconds ?? 0,
            secondaryLimitWindowSeconds: secondary?.limitWindowSeconds
        )
    }
}

// MARK: - Models

private struct CodexAuth: Decodable {
    let tokens: Tokens
    struct Tokens: Decodable {
        let accessToken: String
        let accountId: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }
}

private struct UsageResponse: Decodable {
    let rateLimit: RateLimit?
    enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit" }
}

private struct RateLimit: Decodable {
    let primaryWindow: Window?
    let secondaryWindow: Window?
    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct Window: Decodable {
    let usedPercent: Int
    let resetAt: Int
    let limitWindowSeconds: Int
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }
}
