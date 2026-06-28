import Foundation
import Combine

@MainActor
class UsageState: ObservableObject {
    @Published var claude: FetchState<ClaudeData> = .idle
    @Published var codex: FetchState<CodexData> = .idle
    @Published var lastRefreshed: Date?

    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshClaude() }
            group.addTask { await self.refreshCodex() }
        }
        lastRefreshed = Date()
        pushToESP32()
    }

    private func pushToESP32() {
        guard UserDefaults.standard.bool(forKey: "esp32Enabled"),
              let ip = UserDefaults.standard.string(forKey: "esp32IP"), !ip.isEmpty,
              let url = URL(string: "http://\(ip):8765/usage") else { return }

        var payload: [String: Any] = ["ts": Int(Date().timeIntervalSince1970)]
        if let d = claude.successValue {
            payload["claude5h"] = Int(d.fiveHourPct)
            payload["claude7d"] = Int(d.sevenDayPct ?? 0)
            payload["claude_resets_in"] = Int(d.fiveHourResetsAt?.timeIntervalSinceNow ?? 0)
        }
        if let d = codex.successValue {
            payload["codex"] = d.primaryPct
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req).resume()
    }

    private func refreshClaude() async {
        guard let key = KeychainService.loadClaudeKey() else {
            claude = .error("No session key — open Settings")
            return
        }
        let prev = claude
        if prev.successValue == nil { claude = .loading }
        do {
            claude = .success(try await ClaudeService.fetch(sessionKey: key))
        } catch {
            if let old = prev.successValue {
                claude = .stale(old, error.localizedDescription)
            } else {
                claude = .error(error.localizedDescription)
            }
        }
    }

    private func refreshCodex() async {
        guard CodexService.isConfigured() else {
            codex = .error("~/.codex/auth.json not found")
            return
        }
        let prev = codex
        if prev.successValue == nil { codex = .loading }
        do {
            codex = .success(try await CodexService.fetch())
        } catch {
            if let old = prev.successValue {
                codex = .stale(old, error.localizedDescription)
            } else {
                codex = .error(error.localizedDescription)
            }
        }
    }

    var menuBarTitle: String {
        let showClaude  = UserDefaults.standard.object(forKey: "showClaude")      as? Bool   ?? true
        let showClaude7d = UserDefaults.standard.object(forKey: "showClaude7d")   as? Bool   ?? true
        let showCodex   = UserDefaults.standard.object(forKey: "showCodex")       as? Bool   ?? true
        let labelStyle  = UserDefaults.standard.string(forKey: "menuBarLabelStyle") ?? "circle"
        let style       = UserDefaults.standard.string(forKey: "menuBarStyle") ?? "percent"

        func mkLabel(_ letter: String, _ emoji: String) -> String? {
            switch labelStyle {
            case "none":   return nil
            case "emoji":  return emoji
            case "circle": return letter == "C" ? "Ⓒ" : "Ⓖ"
            default:       return "\(letter):"
            }
        }

        var parts: [String] = []
        if showClaude {
            if let d = claude.successValue {
                parts.append(fmt(label: mkLabel("C", "🤖"),
                                 primary: d.fiveHourPct,
                                 secondary: showClaude7d ? d.sevenDayPct : nil,
                                 style: style))
            } else if case .loading = claude { parts.append("C:…") }
        }
        if showCodex {
            let showCodexSecondary = UserDefaults.standard.object(forKey: "showCodexSecondary") as? Bool ?? true
            if let d = codex.successValue {
                parts.append(fmt(label: mkLabel("G", "💬"),
                                 primary: Double(d.primaryPct),
                                 secondary: showCodexSecondary ? d.secondaryPct.map(Double.init) : nil,
                                 style: style))
            } else if case .loading = codex { parts.append("G:…") }
        }
        return parts.isEmpty ? "⚙" : parts.joined(separator: " · ")
    }

    private func fmt(label: String?, primary: Double, secondary: Double?, style: String) -> String {
        func dot(_ p: Double) -> String { p >= 90 ? "🔴" : p >= 70 ? "🟡" : "🟢" }
        func bar(_ p: Double) -> String {
            let n = min(5, Int(p / 20))
            return String(repeating: "█", count: n) + String(repeating: "░", count: 5 - n)
        }
        func pct(_ p: Double) -> String { "\(Int(p))%" }

        let prefix = label ?? ""
        let peak   = max(primary, secondary ?? 0)

        switch style {
        case "bar":
            return prefix + bar(primary) + (secondary.map { "/" + bar($0) } ?? "")
        case "dot":
            return dot(peak) + prefix + pct(primary) + (secondary.map { "/" + pct($0) } ?? "")
        case "compact":
            return pct(primary) + (secondary.map { "/" + pct($0) } ?? "")
        default: // percent
            return prefix + pct(primary) + (secondary.map { "/" + pct($0) } ?? "")
        }
    }
}
