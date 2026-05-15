import SwiftUI

/// Lets the user pick which attractions appear in the home screen widget.
/// Selection is saved to the App Group UserDefaults so the widget can read it.
struct WidgetConfigurationView: View {
    @Environment(ParkDataStore.self) private var store
    @State private var selectedIDs: Set<String> = []

    private var sortedAttractions: [EntityLiveData] {
        store.attractions.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedAttractions) { attraction in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attraction.name).font(.body)
                            if let wait = attraction.queue?.standby?.waitTime {
                                Text("\(wait) min wait").font(.caption).foregroundStyle(.secondary)
                            } else if attraction.status == "OPERATING" {
                                Text("Operating").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(attraction.status?.capitalized ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedIDs.contains(attraction.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedIDs.contains(attraction.id) {
                            selectedIDs.remove(attraction.id)
                        } else {
                            selectedIDs.insert(attraction.id)
                        }
                        saveSelection()
                    }
                }
            } header: {
                Text("Selected: \(selectedIDs.count) attraction\(selectedIDs.count == 1 ? "" : "s")")
            } footer: {
                Text("Medium widget shows up to 4 attractions. Large widget shows up to 8.")
                    .font(.caption)
            }
        }
        .navigationTitle("Widget Attractions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedIDs = Set(CachedParkData.widgetAttractionIDs) }
    }

    private func saveSelection() {
        // Preserve the user's tap order by keeping the existing order and appending new picks.
        var ordered = CachedParkData.widgetAttractionIDs.filter { selectedIDs.contains($0) }
        for id in selectedIDs where !ordered.contains(id) { ordered.append(id) }
        CachedParkData.widgetAttractionIDs = ordered
    }
}
