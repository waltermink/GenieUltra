import SwiftUI

struct SettingsView: View {
    @Environment(AlertStore.self) private var alertStore
    @Environment(ParkDataStore.self) private var store
    @Environment(PushServerClient.self) private var pushServer

    // MARK: Foreground Polling
    @AppStorage("pollingInterval") private var pollingInterval: Double = 60

    // MARK: Display
    @AppStorage("defaultSort") private var defaultSort: String = "waitTime"

    @State private var systemTestFired = false
    @State private var fireAllFired = false

    // Push server section state
    @State private var serverURLField: String = ""
    @State private var sharedSecretField: String = ""
    @State private var healthMessage: String?
    @State private var serverTestMessage: String?

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Foreground Polling
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Refresh every \(Int(pollingInterval))s while app is open")
                        Slider(value: $pollingInterval, in: 30...180, step: 15)
                    }
                } header: { Text("Foreground Polling") }

                // MARK: Push Server
                Section {
                    TextField("Worker URL", text: $serverURLField, prompt: Text("https://genieultra-push.<sub>.workers.dev"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { pushServer.serverURL = serverURLField }
                    SecureField("Shared secret", text: $sharedSecretField, prompt: Text("Random string set via wrangler secret"))
                        .textInputAutocapitalization(.never)
                        .onSubmit { pushServer.sharedSecret = sharedSecretField }

                    Button("Save & Sync") {
                        pushServer.serverURL    = serverURLField.trimmingCharacters(in: .whitespacesAndNewlines)
                        pushServer.sharedSecret = sharedSecretField.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await pushServer.syncAlerts() }
                    }
                    .disabled(serverURLField.isEmpty || sharedSecretField.isEmpty)

                    pushStatusRow

                    Button {
                        Task {
                            do {
                                let body = try await pushServer.pingHealth()
                                healthMessage = "Connected — \(body.prefix(120))"
                            } catch {
                                healthMessage = "Failed: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        Label("Ping server /health", systemImage: "network")
                    }
                    if let healthMessage { Text(healthMessage).font(.caption2).foregroundStyle(.secondary) }

                    Button {
                        Task {
                            do {
                                try await pushServer.fireServerTest()
                                serverTestMessage = "Push dispatched — check ntfy/Telegram on your phone"
                            } catch {
                                serverTestMessage = "Failed: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        Label("Send test push", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(!pushServer.isConfigured)
                    if let serverTestMessage { Text(serverTestMessage).font(.caption2).foregroundStyle(.secondary) }
                } header: {
                    Text("Push Server (Cloudflare)")
                } footer: {
                    Text("Real-time LL & wait-time alerts via the Cloudflare Worker → ntfy.sh and/or Telegram. Bypasses iOS's 15-minute background polling limit, no Apple Developer Program required. See PushServer/SETUP.md.")
                        .font(.caption)
                }
                .onAppear {
                    if serverURLField.isEmpty    { serverURLField    = pushServer.serverURL }
                    if sharedSecretField.isEmpty { sharedSecretField = pushServer.sharedSecret }
                }

                // MARK: Widget
                Section {
                    NavigationLink("Widget Attractions") {
                        WidgetConfigurationView()
                    }
                } header: {
                    Text("Widget")
                } footer: {
                    Text("Choose which attractions appear on your home screen widget.")
                        .font(.caption)
                }

                // MARK: Defaults
                Section("Defaults") {
                    Picker("Default Sort", selection: $defaultSort) {
                        Text("Wait Time").tag("waitTime")
                        Text("Name").tag("name")
                    }
                }

                // MARK: Notification Test Bench
                Section {
                    Button {
                        Task {
                            await NotificationManager.send(
                                title: "GenieUltra notification test",
                                body: "If you see this, notifications are working correctly.",
                                identifier: "system-test-\(Date().timeIntervalSince1970)"
                            )
                            systemTestFired = true
                            try? await Task.sleep(for: .seconds(2))
                            systemTestFired = false
                        }
                    } label: {
                        Label(
                            systemTestFired ? "Sent!" : "Send test notification",
                            systemImage: systemTestFired ? "checkmark.circle.fill" : "bell.badge"
                        )
                        .foregroundStyle(systemTestFired ? .green : .primary)
                    }

                    Button {
                        Task {
                            await alertStore.fireAllTests()
                            fireAllFired = true
                            try? await Task.sleep(for: .seconds(2))
                            fireAllFired = false
                        }
                    } label: {
                        Label(
                            fireAllFired ? "Fired!" : "Fire all active alerts (bypass conditions)",
                            systemImage: fireAllFired ? "checkmark.circle.fill" : "bolt.fill"
                        )
                        .foregroundStyle(fireAllFired ? .green : .primary)
                    }
                    .disabled(!alertStore.hasActiveAlerts)

                } header: {
                    Text("Notification Test Bench")
                } footer: {
                    Text("\"Fire all\" sends [TEST] notifications unconditionally. Alert conditions are also evaluated continuously while the app is open.")
                        .font(.caption)
                }

                // MARK: About
                Section("About") {
                    Text("Data provided by ThemeParks.wiki")
                    Text("Not affiliated with The Walt Disney Company")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private var pushStatusRow: some View {
        HStack(spacing: 8) {
            switch pushServer.status {
            case .notConfigured:
                Image(systemName: "circle.slash").foregroundStyle(.secondary)
                Text("Not configured").foregroundStyle(.secondary)
            case .syncing:
                ProgressView().controlSize(.small)
                Text("Syncing alert config to worker…")
            case .connected(let lastSync):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected").font(.callout)
                    Text("Last sync \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Error").font(.callout)
                    Text(msg).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }
}
