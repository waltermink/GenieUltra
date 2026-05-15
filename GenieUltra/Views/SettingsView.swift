import SwiftUI

struct SettingsView: View {
    @Environment(AlertStore.self) private var alertStore
    @Environment(ParkDataStore.self) private var store

    @AppStorage("pollingInterval") private var pollingInterval: Double = 60
    @AppStorage(BackgroundRefreshManager.intervalKey) private var backgroundInterval: Double = BackgroundRefreshManager.minimumInterval
    @AppStorage(BackgroundRefreshManager.enabledKey) private var backgroundEnabled: Bool = true
    @AppStorage("defaultSort") private var defaultSort: String = "waitTime"

    @State private var systemTestFired = false
    @State private var fireAllFired = false
    @State private var bgCheckFired = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Foreground Polling
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Foreground refresh: \(Int(pollingInterval))s")
                        Slider(value: $pollingInterval, in: 30...180, step: 15)
                    }
                } header: { Text("Foreground Polling") }

                // MARK: Background Polling
                Section {
                    Toggle("Enable background polling", isOn: $backgroundEnabled)
                    if backgroundEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Interval: \(formatInterval(backgroundInterval))")
                            Slider(
                                value: $backgroundInterval,
                                in: BackgroundRefreshManager.minimumInterval...BackgroundRefreshManager.maximumInterval,
                                step: 60
                            )
                        }
                    }
                } header: {
                    Text("Background Polling")
                } footer: {
                    Text("Background polling wakes the app to check alerts. iOS may delay wakes based on battery and usage — minimum effective interval is ~15 minutes.")
                        .font(.caption)
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
                    // Pipeline sanity check — confirms notifications reach the device.
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

                    // Fires [TEST] notifications for every enabled alert, ignoring cooldowns
                    // and whether the actual conditions are currently met.
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

                    // Runs the real background-fetch alert logic against current live data.
                    // Will only fire for alerts whose conditions are actually met right now.
                    Button {
                        Task {
                            await AlertStore.backgroundCheck(against: store.attractions)
                            bgCheckFired = true
                            try? await Task.sleep(for: .seconds(2))
                            bgCheckFired = false
                        }
                    } label: {
                        Label(
                            bgCheckFired ? "Check complete!" : "Run background check (real conditions)",
                            systemImage: bgCheckFired ? "checkmark.circle.fill" : "arrow.clockwise.circle"
                        )
                        .foregroundStyle(bgCheckFired ? .green : .primary)
                    }
                } header: {
                    Text("Notification Test Bench")
                } footer: {
                    Text("\"Fire all\" sends [TEST] notifications unconditionally. \"Run background check\" uses the same logic as a scheduled background fetch — it only fires if wait times / LL actually meet your criteria right now.")
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

    private func formatInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 1 { return "\(Int(interval))s" }
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }
}
