import Foundation

struct ClaudeData {
    let fiveHourPct: Double
    let sevenDayPct: Double?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
}

struct CodexData {
    let primaryPct: Int
    let secondaryPct: Int?
    let primaryResetsAt: Date?
    let secondaryResetsAt: Date?
    let limitWindowSeconds: Int
    let secondaryLimitWindowSeconds: Int?
}

enum FetchState<T> {
    case idle, loading
    case success(T)
    case stale(T, String)
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var successValue: T? {
        switch self {
        case .success(let v), .stale(let v, _): return v
        default: return nil
        }
    }

    var staleMessage: String? {
        if case .stale(_, let msg) = self { return msg }
        return nil
    }
}

enum ServiceError: LocalizedError {
    case noOrgFound
    case authFileNotFound
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noOrgFound: return "No Claude org found"
        case .authFileNotFound: return "~/.codex/auth.json not found — login to Codex CLI first"
        case .httpError(let code):
            switch code {
            case 401: return "Session expired — tap Re-detect"
            case 403: return "Access denied — check your Claude plan"
            case 429: return "Rate limited — retrying..."
            case 500...599: return "Server error (\(code)) — will retry"
            default: return "HTTP \(code)"
            }
        }
    }
}
