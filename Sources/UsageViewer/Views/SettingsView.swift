import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: UsageState
    @Environment(\.dismiss) var dismiss

    @State private var sessionKey: String = KeychainService.loadClaudeKey() ?? ""
    @State private var saveError: String?
    @State private var detectStatus: String?
    @State private var isDetecting = false

    @AppStorage("showClaude")         var showClaude         = true
    @AppStorage("showClaude7d")       var showClaude7d       = true
    @AppStorage("showCodex")          var showCodex          = true
    @AppStorage("showCodexSecondary") var showCodexSecondary = true
    @AppStorage("menuBarStyle")       var menuBarStyle       = "percent"
    @AppStorage("menuBarLabels")      var menuBarLabels      = true
    @AppStorage("esp32Enabled")       var esp32Enabled       = false
    @AppStorage("esp32IP")            var esp32IP            = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.headline)

            GroupBox("Claude") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            isDetecting = true
                            detectStatus = nil
                            DispatchQueue.global().async {
                                let found = BrowserCookieService.claudeSessionKey()
                                DispatchQueue.main.async {
                                    isDetecting = false
                                    if let key = found {
                                        sessionKey = key
                                        detectStatus = "✓ Found in browser"
                                    } else {
                                        detectStatus = "Not found — paste manually below"
                                    }
                                }
                            }
                        } label: {
                            Label("Auto-detect from browser", systemImage: "magnifyingglass")
                        }
                        .disabled(isDetecting)
                        if isDetecting { ProgressView().scaleEffect(0.7) }
                    }
                    if let status = detectStatus {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(status.hasPrefix("✓") ? .green : .secondary)
                    }

                    Divider()

                    Text("Or paste manually:").font(.caption.weight(.medium))
                    SecureField("sessionKey (from claude.ai cookies)", text: $sessionKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Chrome → DevTools (F12) → Application → Cookies → claude.ai → sessionKey")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            GroupBox("ChatGPT / Codex CLI") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: CodexService.isConfigured()
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(CodexService.isConfigured() ? .green : .secondary)
                        Text(CodexService.isConfigured()
                             ? "~/.codex/auth.json detected"
                             : "~/.codex/auth.json not found")
                        .font(.caption)
                    }
                    if !CodexService.isConfigured() {
                        Text("Run `codex login` in Terminal to authenticate the Codex CLI first.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            GroupBox("Display") {
                VStack(alignment: .leading, spacing: 10) {
                    // Visibility
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Show Claude", isOn: $showClaude)
                        if showClaude {
                            Toggle("  · Show 7-day quota bar", isOn: $showClaude7d)
                                .padding(.leading, 8)
                        }
                        Toggle("Show ChatGPT / Codex", isOn: $showCodex)
                        if showCodex {
                            Toggle("  · Show secondary window bar", isOn: $showCodexSecondary)
                                .padding(.leading, 8)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Divider()

                    // Menu bar style
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Menu bar style").font(.caption.weight(.medium))
                        Picker("", selection: $menuBarStyle) {
                            Text("% — C:17%/9%").tag("percent")
                            Text("Bar — C:███░░/█░░░░").tag("bar")
                            Text("Dot — 🟢C:17%/9%").tag("dot")
                            Text("Compact — 17%/9%").tag("compact")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Toggle("Show provider labels (C: G:)", isOn: $menuBarLabels)
                            .toggleStyle(.checkbox)
                            .disabled(menuBarStyle == "dot")
                    }
                }
                .padding(4)
            }

            GroupBox("ESP32 Display") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Push data to ESP32 after each refresh", isOn: $esp32Enabled)
                        .toggleStyle(.checkbox)
                    if esp32Enabled {
                        HStack {
                            Text("IP").font(.caption.weight(.medium)).frame(width: 20)
                            TextField("192.168.x.200", text: $esp32IP)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                        }
                        Text("ESP32 must run HTTP server on port 8765 — see plan for firmware.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            if let err = saveError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save & Refresh") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func save() {
        saveError = nil
        if !sessionKey.isEmpty {
            do {
                try KeychainService.saveClaudeKey(sessionKey.trimmingCharacters(in: .whitespaces))
            } catch {
                saveError = "Save error: \(error.localizedDescription)"
                return
            }
        }
        Task {
            await state.refresh()
            dismiss()
        }
    }
}
