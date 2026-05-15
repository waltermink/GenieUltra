import SwiftUI

struct DashboardView: View {
    @Environment(ParkDataStore.self) private var store
    @Environment(AlertStore.self) private var alertStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            AttractionsView()
                .tabItem {
                    Label("Attractions", systemImage: "ticket")
                }
            ShowsView()
                .tabItem {
                    Label("Shows", systemImage: "theatermasks")
                }
            AlertsView()
                .tabItem {
                    Label("Alerts", systemImage: "bell.badge")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await store.initialLoad()
            store.startPolling()
            await NotificationManager.requestPermission()
        }
        .onChange(of: store.attractions) { _, newAttractions in
            guard alertStore.hasActiveAlerts else { return }
            Task { await alertStore.checkAlerts(against: newAttractions) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                alertStore.reload()
                Task { await store.refreshLiveData() }
                store.startPolling()
            case .background:
                store.stopPolling()
                BackgroundRefreshManager.scheduleNextRefresh()
            case .inactive:
                store.stopPolling()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Preview Store

extension ParkDataStore {
    static func previewStore() -> ParkDataStore {
        let store = ParkDataStore()
        store.lastRefreshed = Date()
        store.schedule = ScheduleEntry(
            date: "2026-05-15",
            type: "OPERATING",
            openingTime: "2026-05-15T09:00:00-04:00",
            closingTime: "2026-05-15T23:00:00-04:00"
        )

        let sampleForecast: [ForecastEntry] = {
            let calendar = Calendar.current
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let base = calendar.startOfDay(for: Date())
            let waits = [40, 50, 65, 70, 80, 85, 90, 95, 100, 85, 75, 60, 45, 30]
            return waits.enumerated().map { i, w in
                ForecastEntry(time: formatter.string(from: calendar.date(byAdding: .hour, value: 9 + i, to: base)!),
                              waitTime: w, percentage: w)
            }
        }()

        store.attractions = [
            EntityLiveData(id: "1", name: "Space Mountain", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 45),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-05-15T14:30:00", returnEnd: nil),
                    paidReturnTime: nil), showtimes: nil, forecast: sampleForecast),
            EntityLiveData(id: "2", name: "Seven Dwarfs Mine Train", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 90),
                    returnTime: ReturnTimeQueue(state: "FINISHED", returnStart: nil, returnEnd: nil),
                    paidReturnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-05-15T16:00:00", returnEnd: nil)),
                showtimes: nil, forecast: sampleForecast),
            EntityLiveData(id: "3", name: "Big Thunder Mountain Railroad", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 35),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil, forecast: nil),
            EntityLiveData(id: "4", name: "Haunted Mansion", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 25),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil, forecast: nil),
            EntityLiveData(id: "5", name: "Pirates of the Caribbean", entityType: "ATTRACTION", status: "DOWN", lastUpdated: nil,
                queue: nil, showtimes: nil, forecast: nil),
            EntityLiveData(id: "6", name: "it's a small world", entityType: "ATTRACTION", status: "CLOSED", lastUpdated: nil,
                queue: nil, showtimes: nil, forecast: nil),
            EntityLiveData(id: "7", name: "Tomorrowland Speedway", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 10),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil, forecast: nil),
            // Meet-and-greet (SHOW type with queue — promoted to attractions)
            EntityLiveData(id: "mg1", name: "Mickey & Minnie Mouse", entityType: "SHOW", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 20),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil, forecast: nil),
        ]

        // Simulate that Pirates, it's a small world, and the meet-and-greet were previously seen with queues
        store.knownQueueAttractionIDs = ["1", "2", "3", "4", "5", "6", "7", "mg1"]

        store.shows = [
            EntityLiveData(id: "s1", name: "Happily Ever After", entityType: "SHOW", status: "OPERATING", lastUpdated: nil, queue: nil,
                showtimes: [ShowTime(type: "PERFORMANCE", startTime: "2026-05-15T21:00:00-04:00", endTime: nil)],
                forecast: nil),
            EntityLiveData(id: "s2", name: "Festival of Fantasy Parade", entityType: "SHOW", status: "OPERATING", lastUpdated: nil, queue: nil,
                showtimes: [ShowTime(type: "PERFORMANCE", startTime: "2026-05-15T15:00:00-04:00", endTime: nil)],
                forecast: nil),
        ]

        return store
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environment(ParkDataStore.previewStore())
        .environment(AlertStore())
}
