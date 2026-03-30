import SwiftUI

struct AttractionsView: View {
    @Environment(ParkDataStore.self) private var store
    @Binding var selectedPark: ParkSelection
    @State private var sortOption: SortOption = .waitTime
    @State private var filterOption: FilterOption = .operating

    // MARK: - Computed Properties

    private var currentAttractions: [EntityLiveData] {
        let source = selectedPark == .disneyland
            ? store.disneylandAttractions
            : store.californiaAdventureAttractions
        return applyFiltersAndSort(to: source)
    }

    private var currentSchedule: ScheduleEntry? {
        selectedPark == .disneyland
            ? store.disneylandSchedule
            : store.californiaAdventureSchedule
    }

    private var isFilterActive: Bool {
        filterOption != .all
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.lastRefreshed == nil {
                    loadingView
                } else if let error = store.error, store.lastRefreshed == nil {
                    errorView(error)
                } else {
                    mainContent
                }
            }
            .navigationTitle("Attractions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    parkSwitcher
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
            }
        }
    }

    // MARK: - Toolbar Items

    private var parkSwitcher: some View {
        Menu {
            Picker("Park", selection: $selectedPark) {
                ForEach(ParkSelection.allCases, id: \.self) { park in
                    Text(park.rawValue).tag(park)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedPark.rawValue)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $filterOption) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Image(systemName: isFilterActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOption) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading park data...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Unable to load data")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await store.initialLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            Section {
                ParkHeaderView(
                    schedule: currentSchedule,
                    lastRefreshed: store.lastRefreshed
                )
            }

            if let error = store.error, store.consecutiveFailures > 0 {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                    }
                }
            }

            Section("Attractions") {
                ForEach(currentAttractions) { attraction in
                    NavigationLink {
                        AttractionDetailView(
                            attraction: attraction,
                            history: waitTimeHistory(for: attraction.id)
                        )
                    } label: {
                        AttractionRowView(attraction: attraction)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await store.refreshLiveData()
        }
    }

    // MARK: - Helpers

    private func applyFiltersAndSort(to attractions: [EntityLiveData]) -> [EntityLiveData] {
        var filtered = attractions

        switch filterOption {
        case .all:
            break
        case .operating:
            filtered = filtered.filter { $0.status == "OPERATING" }
        case .lightningLane:
            filtered = filtered.filter {
                $0.queue?.returnTime != nil || $0.queue?.paidReturnTime != nil
            }
        }

        switch sortOption {
        case .waitTime:
            filtered.sort {
                ($0.queue?.standby?.waitTime ?? -1) > ($1.queue?.standby?.waitTime ?? -1)
            }
        case .name:
            filtered.sort { $0.name < $1.name }
        }

        return filtered
    }

    private func waitTimeHistory(for entityID: String) -> [WaitTimeRecord] {
        store.waitTimeHistory[entityID] ?? []
    }
}

#Preview("Attractions") {
    AttractionsView(selectedPark: .constant(.disneyland))
        .environment(ParkDataStore.previewStore())
}
