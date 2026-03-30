import SwiftUI

struct SettingsView: View {
    @AppStorage("pollingInterval") private var pollingInterval: Double = 60
    @AppStorage("defaultPark") private var defaultPark: String = "disneyland"
    @AppStorage("defaultSort") private var defaultSort: String = "waitTime"

    var body: some View {
        NavigationStack {
            Form {
                Section("Polling") {
                    VStack(alignment: .leading) {
                        Text("Refresh interval: \(Int(pollingInterval))s")
                        Slider(value: $pollingInterval, in: 60...180, step: 15)
                    }
                }

                Section("Defaults") {
                    Picker("Default Park", selection: $defaultPark) {
                        Text("Disneyland").tag("disneyland")
                        Text("California Adventure").tag("californiaAdventure")
                    }

                    Picker("Default Sort", selection: $defaultSort) {
                        Text("Wait Time").tag("waitTime")
                        Text("Name").tag("name")
                    }
                }

                Section("About") {
                    Text("Data provided by ThemeParks.wiki")
                    Text("Not affiliated with The Walt Disney Company")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
