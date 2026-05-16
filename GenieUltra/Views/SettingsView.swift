import SwiftUI

struct SettingsView: View {
    @Environment(AlertStore.self) private var alertStore
    @Environment(ParkDataStore.self) private var store

    // MARK: Foreground Polling
    @AppStorage("pollingInterval") private var pollingInterval: Double = 60

    // MARK: Background — Full Sweep
    @AppStorage(BackgroundRefreshManager.intervalKey) private var backgroundInterval: Double = BackgroundRefreshManager.minimumInterval
    @AppStorage(BackgroundRefreshManager.enabledKey)  private var backgroundEnabled: Bool = true

    // MARK: Background — Targeted Wait Time
    @AppStorage(BackgroundRefreshManager.targetedWaitIntervalKey) private var targetedWaitInterval: Double = 5 * 60
    @AppStorage(BackgroundRefreshManager.targetedWaitEnabledKey)  private var targetedWaitEnabled: Bool = true

    // MARK: Background — Targeted Lightning Lane
    @AppStorage(BackgroundRefreshManager.targetedLLIntervalKey) private var targetedLLInterval: Double = 3 * 60
    @AppStorage(BackgroundRefreshManager.targetedLLEnabledKey)  private var targetedLLEnabled: Bool = true

    // MARK: Display
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
                        Text("Refresh every \(Int(pollingInterval))s while app is open")
                        Slider(value: $pollingInterval, in: 30...180, step: 15)
                    }
                } header: { Text("Foreground Polling") }

                // MARK: Background — Full Sweep
                Section {
                    Toggle("Enable full-sweep polling", isOn: $backgroundEnabled)
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
                    Text("Background — Full Sweep")
                } footer: {
                    Text("Fetches all park entities, updates the widget, and checks every active alert. iOS enforces ~15 min minimum regardless of this setting.")
                        .font(.caption)
                }

                // MARK: Background — Targeted Wait Time
                Section {
                    Toggle("Enable targeted wait-time polling", isOn: $targetedWaitEnabled)
                    if targetedWaitEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Interval: \(formatInterval(targetedWaitInterval))")
                            Slider(
                                value: $targetedWaitInterval,
                                in: BackgroundRefreshManager.targetedMinInterval...BackgroundRefreshManager.targetedMaxInterval,
                                step: 60
                            )
                        }
                    }
                } header: {
                    Text("Background — Targeted Wait Time")
                } footer: {
                    Text("Only checks attractions you're monitoring for wait-time alerts. Records history for those attractions so graphs stay current even when the app is closed.")
                        .font(.caption)
                }

                // MARK: Background — Targeted Lightning Lane
                Section {
                    Toggle("Enable Lightning Lane polling", isOn: $targetedLLEnabled)
                    if targetedLLEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Interval: \(formatInterval(targetedLLInterval))")
                            Slider(
                                value: $targetedLLInterval,
                                in: BackgroundRefreshManager.targetedMinInterval...BackgroundRefreshManager.targetedMaxInterval,
                                step: 60
                            )
                        }
                    }
                } header: {
                    Text("Background — Lightning Lane")
                } footer: {
                    Text("Only evaluates Lightning Lane availability alerts. Set this more aggressively than wait-time polling since LL windows open and close quickly.")
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
