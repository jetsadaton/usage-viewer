import Foundation

enum ClaudeService {
    static func fetch(sessionKey: String) async throws -> ClaudeData {
        let orgUUID = try await getOrgUUID(sessionKey: sessionKey)
        return try await getUsage(orgUUID: orgUUID, sessionKey: sessionKey)
    }

    private static func getOrgUUID(sessionKey: String) async throws -> String {
        let req = claudeRequest(path: "/api/organizations", sessionKey: sessionKey)
        let (data, _) = try await withRetry {
            let (d, r) = try await URLSession.shared.data(for: req)
            try checkStatus(r)
            return (d, r)
        }
        let orgs = try JSONDecoder().decode([ClaudeOrg].self, from: data)
        guard let uuid = orgs.first?.uuid else { throw ServiceError.noOrgFound }
        return uuid
    }

    private static func getUsage(orgUUID: String, sessionKey: String) async throws -> ClaudeData {
        let req = claudeRequest(path: "/api/organizations/\(orgUUID)/usage", sessionKey: sessionKey)
        let (data, _) = try await withRetry {
            let (d, r) = try await URLSession.shared.data(for: req)
            try checkStatus(r)
            return (d, r)
        }
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        return ClaudeData(
            fiveHourPct: decoded.fiveHour?.utilization ?? 0,   // API already returns 0–100
            sevenDayPct: decoded.sevenDay?.utilization,
            fiveHourResetsAt: parseDate(decoded.fiveHour?.resetsAt),
            sevenDayResetsAt: parseDate(decoded.sevenDay?.resetsAt)
        )
    }

    private static func claudeRequest(path: String, sessionKey: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://claude.ai\(path)")!)
        req.timeoutInterval = 15
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        return req
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else { throw ServiceError.httpError(http.statusCode) }
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Response models

private struct ClaudeOrg: Decodable { let uuid: String }

private struct UsageResponse: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct Window: Decodable {
    let utilization: Double?
    let resetsAt: String?
    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
