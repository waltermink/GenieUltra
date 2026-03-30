import Foundation
import SwiftUI

@MainActor
@Observable
class ParkDataStore {
    // MARK: - Published State

    var disneylandParkID: String = ""
    var californiaAdventureParkID: String = ""

    var disneylandAttractions: [EntityLiveData] = []
    var californiaAdventureAttractions: [EntityLiveData] = []
    var disneylandShows: [EntityLiveData] = []
    var californiaAdventureShows: [EntityLiveData] = []

    var disneylandSchedule: ScheduleEntry?
    var californiaAdventureSchedule: ScheduleEntry?

    var lastRefreshed: Date?
    var isLoading = false
    var error: String?
    var consecutiveFailures = 0

    var waitTimeHistory: [String: [WaitTimeRecord]] = [:]

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?

    // MARK: - Initial Load

    func initialLoad() async {
        isLoading = true
        error = nil

        do {
            try await resolveParkIDs()

            // Fetch live data and schedules for both parks in parallel
            async let dlLive = ThemeParksAPI.fetchEntityLiveData(entityID: disneylandParkID)
            async let caLive = ThemeParksAPI.fetchEntityLiveData(entityID: californiaAdventureParkID)
            async let dlSchedule = ThemeParksAPI.fetchEntitySchedule(entityID: disneylandParkID)
            async let caSchedule = ThemeParksAPI.fetchEntitySchedule(entityID: californiaAdventureParkID)

            let (dlLiveResult, caLiveResult, dlScheduleResult, caScheduleResult) =
                try await (dlLive, caLive, dlSchedule, caSchedule)

            processLiveData(dlLiveResult, for: .disneyland)
            processLiveData(caLiveResult, for: .californiaAdventure)
            processSchedule(dlScheduleResult, for: .disneyland)
            processSchedule(caScheduleResult, for: .californiaAdventure)

            lastRefreshed = Date()
            consecutiveFailures = 0

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Refresh

    func refreshLiveData() async {
        guard !disneylandParkID.isEmpty, !californiaAdventureParkID.isEmpty else { return }

        do {
            async let dlLive = ThemeParksAPI.fetchEntityLiveData(entityID: disneylandParkID)
            async let caLive = ThemeParksAPI.fetchEntityLiveData(entityID: californiaAdventureParkID)

            let (dlResult, caResult) = try await (dlLive, caLive)

            processLiveData(dlResult, for: .disneyland)
            processLiveData(caResult, for: .californiaAdventure)

            lastRefreshed = Date()
            consecutiveFailures = 0
            error = nil

        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                self.error = "Unable to refresh — showing older data"
            }
        }
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await refreshLiveData()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Private Helpers

    private func resolveParkIDs() async throws {
        let defaults = UserDefaults.standard
        if let dlID = defaults.string(forKey: "disneylandParkID"),
           let caID = defaults.string(forKey: "californiaAdventureParkID"),
           !dlID.isEmpty, !caID.isEmpty {
            disneylandParkID = dlID
            californiaAdventureParkID = caID
            return
        }

        let destinations = try await ThemeParksAPI.fetchDestinations()
        guard let dlr = destinations.destinations.first(where: {$0.slug == "disneylandresort"})
        else {
            throw APIError.invalidResponse
        }

        for park in dlr.parks {
            let name = park.name.lowercased()
            if name.contains("california adventure") {
                californiaAdventureParkID = park.id
            } else if name.contains("disneyland") {
                disneylandParkID = park.id
            }
        }

        guard !disneylandParkID.isEmpty, !californiaAdventureParkID.isEmpty else {
            throw APIError.invalidResponse
        }

        defaults.set(disneylandParkID, forKey: "disneylandParkID")
        defaults.set(californiaAdventureParkID, forKey: "californiaAdventureParkID")
    }

    private func processLiveData(_ response: EntityLiveDataResponse, for park: Park) {
        let attractions = response.liveData.filter { $0.entityType == "ATTRACTION" }
        let shows = response.liveData.filter { $0.entityType == "SHOW" }

        // Record wait time history
        let now = Date()
        for attraction in attractions {
            if let waitTime = attraction.queue?.standby?.waitTime {
                var history = waitTimeHistory[attraction.id] ?? []
                history.append(WaitTimeRecord(date: now, waitTime: waitTime))
                if history.count > 120 {
                    history = Array(history.suffix(120))
                }
                waitTimeHistory[attraction.id] = history
            }
        }

        switch park {
        case .disneyland:
            disneylandAttractions = attractions
            disneylandShows = shows
        case .californiaAdventure:
            californiaAdventureAttractions = attractions
            californiaAdventureShows = shows
        }
    }

    private func processSchedule(_ response: EntityScheduleResponse, for park: Park) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let todaySchedule = response.schedule.first { entry in
            entry.date == today && entry.type == "OPERATING"
        }

        switch park {
        case .disneyland:
            disneylandSchedule = todaySchedule
        case .californiaAdventure:
            californiaAdventureSchedule = todaySchedule
        }
    }
}

enum Park {
    case disneyland
    case californiaAdventure
}
