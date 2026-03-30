import SwiftUI

enum ParkSelection: String, CaseIterable {
    case disneyland = "Disneyland"
    case californiaAdventure = "California Adventure"
}

struct DashboardView: View {
    @Environment(ParkDataStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPark: ParkSelection = .disneyland

    var body: some View {
        TabView {
            AttractionsView(selectedPark: $selectedPark)
                .tabItem {
                    Label("Attractions", systemImage: "ticket")
                }
            ShowsView(selectedPark: $selectedPark)
                .tabItem {
                    Label("Shows", systemImage: "theatermasks")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await store.initialLoad()
            store.startPolling()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await store.refreshLiveData() }
                store.startPolling()
            case .background, .inactive:
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
        store.disneylandSchedule = ScheduleEntry(
            date: "2026-03-30",
            type: "OPERATING",
            openingTime: "2026-03-30T08:00:00-07:00",
            closingTime: "2026-03-30T00:00:00-07:00"
        )
        store.californiaAdventureSchedule = ScheduleEntry(
            date: "2026-03-30",
            type: "OPERATING",
            openingTime: "2026-03-30T08:00:00-07:00",
            closingTime: "2026-03-30T22:00:00-07:00"
        )

        store.disneylandAttractions = [
            EntityLiveData(id: "1", name: "Space Mountain", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 45),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T14:30:00", returnEnd: nil),
                    paidReturnTime: nil), showtimes: nil),
            EntityLiveData(id: "2", name: "TRON Lightcycle / Run", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 90),
                    returnTime: ReturnTimeQueue(state: "FINISHED", returnStart: nil, returnEnd: nil),
                    paidReturnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T16:00:00", returnEnd: nil)), showtimes: nil),
            EntityLiveData(id: "3", name: "Matterhorn Bobsleds", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 60),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T15:15:00", returnEnd: nil),
                    paidReturnTime: nil), showtimes: nil),
            EntityLiveData(id: "4", name: "Big Thunder Mountain Railroad", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 35),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil),
            EntityLiveData(id: "5", name: "Haunted Mansion", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 25),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil),
            EntityLiveData(id: "6", name: "Pirates of the Caribbean", entityType: "ATTRACTION", status: "DOWN", lastUpdated: nil,
                queue: nil, showtimes: nil),
            EntityLiveData(id: "7", name: "Splash Mountain", entityType: "ATTRACTION", status: "REFURBISHMENT", lastUpdated: nil,
                queue: nil, showtimes: nil),
            EntityLiveData(id: "8", name: "it's a small world", entityType: "ATTRACTION", status: "CLOSED", lastUpdated: nil,
                queue: nil, showtimes: nil),
        ]

        store.disneylandShows = [
            EntityLiveData(id: "s1", name: "Fantasmic!", entityType: "SHOW", status: "OPERATING", lastUpdated: nil, queue: nil,
                showtimes: [
                    ShowTime(type: "PERFORMANCE", startTime: "2026-03-30T21:00:00-07:00", endTime: nil),
                    ShowTime(type: "PERFORMANCE", startTime: "2026-03-30T22:30:00-07:00", endTime: nil),
                ]),
            EntityLiveData(id: "s2", name: "Wondrous Journeys", entityType: "SHOW", status: "OPERATING", lastUpdated: nil, queue: nil,
                showtimes: [
                    ShowTime(type: "PERFORMANCE", startTime: "2026-03-30T21:30:00-07:00", endTime: nil),
                ]),
        ]

        store.californiaAdventureAttractions = [
            EntityLiveData(id: "c1", name: "Radiator Springs Racers", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 75),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T15:45:00", returnEnd: nil),
                    paidReturnTime: nil), showtimes: nil),
            EntityLiveData(id: "c2", name: "Guardians of the Galaxy – Mission: BREAKOUT!", entityType: "ATTRACTION", status: "OPERATING", lastUpdated: nil,
                queue: QueueData(standby: StandbyQueue(waitTime: 55),
                    returnTime: nil, paidReturnTime: nil), showtimes: nil),
        ]

        return store
    }
}

#Preview("Dashboard") {
    DashboardView()
        .environment(ParkDataStore.previewStore())
}
