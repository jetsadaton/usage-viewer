import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: UsageState
    @State private var showSettings = false

    @AppStorage("showClaude")        var showClaude        = true
    @AppStorage("showClaude7d")      var showClaude7d      = true
    @AppStorage("showCodex")         var showCodex         = true
    @AppStorage("showCodexSecondary") var showCodexSecondary = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("AI Usage").font(.headline)
                Spacer()
                Button { Task { await state.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).help("Refresh now")

                Button { showSettings = true } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain).help("Settings")
            }

            Divider()

            // Claude
            if showClaude {
                ProviderRow(
                    name: "Claude",
                    icon: "c.circle.fill",
                    color: .orange,
                    primaryPercent: claudePercent,
                    primaryLabel: "5h",
                    secondaryPercent: showClaude7d ? claudeWeeklyPercent : nil,
                    secondaryLabel: "7d",
                    resetInfo: claudeResetInfo,
                    errorMsg: claudeError,
                    isLoading: state.claude.isLoading,
                    staleMsg: claudeStaleMsg,
                    onRedetect: {
                        Task.detached {
                            if let key = BrowserCookieService.claudeSessionKey() {
                                try? KeychainService.saveClaudeKey(key)
                                Task { @MainActor in await state.refresh() }
                            }
                        }
                    }
                )
            }

            // Codex / ChatGPT
            if showCodex {
                ProviderRow(
                    name: "ChatGPT / Codex",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .green,
                    primaryPercent: codexPercent,
                    primaryLabel: codexWindowLabel,
                    secondaryPercent: showCodexSecondary ? codexSecondaryPercent : nil,
                    secondaryLabel: codexSecondaryLabel,
                    resetInfo: codexResetInfo,
                    errorMsg: codexError,
                    isLoading: state.codex.isLoading,
                    staleMsg: codexStaleMsg
                )
            }

            Divider()

            HStack {
                if let t = state.lastRefreshed {
                    Text("Updated \(t.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 300)
        .sheet(isPresented: $showSettings) {
            SettingsView(state: state)
        }
    }

    // MARK: - Claude

    private var claudePercent: Double? {
        state.claude.successValue.map(\.fiveHourPct)
    }
    private var claudeWeeklyPercent: Double? {
        state.claude.successValue?.sevenDayPct
    }
    private var claudeResetInfo: String? {
        guard let d = state.claude.successValue, let r = d.fiveHourResetsAt else { return nil }
        return "resets \(resetLabel(r))"
    }
    private var claudeError: String? {
        if case .error(let msg) = state.claude { return msg }
        return nil
    }
    private var claudeStaleMsg: String? { state.claude.staleMessage }

    // MARK: - Codex

    private var codexPercent: Double? {
        state.codex.successValue.map { Double($0.primaryPct) }
    }
    private var codexSecondaryPercent: Double? {
        state.codex.successValue?.secondaryPct.map(Double.init)
    }
    private var codexWindowLabel: String? {
        state.codex.successValue.map { windowLabel($0.limitWindowSeconds) }
    }
    private var codexSecondaryLabel: String? {
        guard let d = state.codex.successValue, let s = d.secondaryLimitWindowSeconds else { return "2nd" }
        return windowLabel(s)
    }
    private var codexResetInfo: String? {
        guard let d = state.codex.successValue, let r = d.primaryResetsAt else { return nil }
        var s = "resets \(resetLabel(r))"
        if let r2 = d.secondaryResetsAt, let label = codexSecondaryLabel {
            s += " · \(label) resets \(resetLabel(r2))"
        }
        return s
    }
    private func windowLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "?" }
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        return "\(seconds / 3600)h"
    }
    private var codexError: String? {
        if case .error(let msg) = state.codex { return msg }
        return nil
    }
    private var codexStaleMsg: String? { state.codex.staleMessage }

    private func resetLabel(_ date: Date) -> String {
        let delta = date.timeIntervalSinceNow
        guard delta > 0 else { return "soon" }
        let h = Int(delta / 3600)
        let m = Int(delta.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "in \(h)h \(m)m" : "in \(m)m"
    }
}

// MARK: - ProviderRow

struct ProviderRow: View {
    let name: String
    let icon: String
    let color: Color
    let primaryPercent: Double?
    let primaryLabel: String?
    let secondaryPercent: Double?
    let secondaryLabel: String?
    let resetInfo: String?
    let errorMsg: String?
    let isLoading: Bool
    var staleMsg: String? = nil
    var onRedetect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title row
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(name).font(.subheadline.weight(.medium))
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                } else if errorMsg != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                } else if staleMsg != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            // Primary bar
            if let pct = primaryPercent {
                QuotaBar(percent: pct, label: primaryLabel)
            }

            // Secondary bar (7-day / secondary window)
            if let pct = secondaryPercent {
                QuotaBar(percent: pct, label: secondaryLabel)
            }

            // Reset / error info
            if let info = resetInfo {
                Text(info).font(.caption2).foregroundStyle(.secondary)
            }
            if let err = errorMsg {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
            let sessionExpiredMsg = (errorMsg ?? staleMsg) ?? ""
            if sessionExpiredMsg.contains("Session expired"), let action = onRedetect {
                Button("Re-detect", action: action)
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - QuotaBar

struct QuotaBar: View {
    let percent: Double
    let label: String?

    var body: some View {
        HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
            }
            ProgressView(value: percent / 100)
                .tint(barColor)
            Text("\(Int(percent))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(barColor)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var barColor: Color {
        percent >= 90 ? .red : percent >= 70 ? .orange : .primary
    }
}
