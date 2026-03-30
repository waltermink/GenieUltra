import SwiftUI

struct ShowsView: View {
    @Environment(ParkDataStore.self) private var store
    @Binding var selectedPark: ParkSelection
    @State private var showFilterOption: ShowFilterOption = .todayScheduled

    // MARK: - Computed Properties

    private var currentShows: [EntityLiveData] {
        let source = selectedPark == .disneyland
            ? store.disneylandShows
            : store.californiaAdventureShows
        return applyShowFilter(to: source)
    }

    private var currentSchedule: ScheduleEntry? {
        selectedPark == .disneyland
            ? store.disneylandSchedule
            : store.californiaAdventureSchedule
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
            .navigationTitle("Shows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    parkSwitcher
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
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
            Picker("Shows", selection: $showFilterOption) {
                ForEach(ShowFilterOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Image(systemName: showFilterOption != .all
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
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

            Section("Shows & Entertainment") {
                if currentShows.isEmpty {
                    Text("No shows scheduled for today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(currentShows) { show in
                        ShowRowView(show: show)
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

    private func applyShowFilter(to shows: [EntityLiveData]) -> [EntityLiveData] {
        switch showFilterOption {
        case .all:
            return shows
        case .todayScheduled:
            return shows.filter { show in
                guard let showtimes = show.showtimes, !showtimes.isEmpty else { return false }
                return showtimes.contains { showtime in
                    guard let startStr = showtime.startTime,
                          let startDate = TimeFormatter.parseISO(startStr) else { return false }
                    return Calendar.current.isDateInToday(startDate)
                }
            }
        }
    }
}

#Preview("Shows") {
    ShowsView(selectedPark: .constant(.disneyland))
        .environment(ParkDataStore.previewStore())
}
