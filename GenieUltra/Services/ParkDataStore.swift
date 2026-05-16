import Foundation
import SwiftUI

@MainActor
@Observable
class ParkDataStore {
    // MARK: - Published State

    var magicKingdomParkID: String = ""

    var attractions: [EntityLiveData] = []
    var shows: [EntityLiveData] = []
    var schedule: ScheduleEntry?

    // Persisted set of attraction IDs known to have a standby queue,
    // so DOWN/CLOSED rides still appear in the queue filter.
    var knownQueueAttractionIDs: Set<String>

    var lastRefreshed: Date?
    var isLoading = false
    var error: String?
    var consecutiveFailures = 0

    var waitTimeHistory: [String: [WaitTimeRecord]] = [:]

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "knownQueueAttractionIDs") ?? []
        knownQueueAttractionIDs = Set(saved)
        // Seed graphs with any data collected during previous sessions or background tasks.
        waitTimeHistory = PersistedWaitHistory.load()
    }

    // MARK: - Initial Load

    func initialLoad() async {
        error = nil

        // Show cached data from a previous session or background refresh immediately
        // so the user sees content before the network request completes.
        if let cached = CachedParkData.load() {
            processLiveData(cached, saveToCache: false)
            lastRefreshed = CachedParkData.lastSaved
        } else {
            isLoading = true
        }

        do {
            try await resolveParkID()

            async let liveData = ThemeParksAPI.fetchEntityLiveData(entityID: magicKingdomParkID)
            async let scheduleData = ThemeParksAPI.fetchEntitySchedule(entityID: magicKingdomParkID)

            let (liveResult, scheduleResult) = try await (liveData, scheduleData)

            processLiveData(liveResult)
            processSchedule(scheduleResult)

            lastRefreshed = Date()
            consecutiveFailures = 0

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Refresh

    func refreshLiveData() async {
        guard !magicKingdomParkID.isEmpty else { return }

        do {
            let liveResult = try await ThemeParksAPI.fetchEntityLiveData(entityID: magicKingdomParkID)
            processLiveData(liveResult)

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
                let raw = UserDefaults.standard.double(forKey: "pollingInterval")
                let interval = raw >= 30 ? raw : 60
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await refreshLiveData()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Merge wait-time history written by background tasks into the in-memory store.
    /// Call when the app returns to the foreground so graphs reflect background data.
    func mergePersistedHistory() {
        let persisted = PersistedWaitHistory.load()
        for (id, records) in persisted {
            let current = waitTimeHistory[id]
            // Replace when persisted has more data than what's in memory (background added points).
            if current == nil || records.count > (current?.count ?? 0) {
                waitTimeHistory[id] = Array(records.suffix(PersistedWaitHistory.maxRecordsPerAttraction))
            }
        }
    }

    // MARK: - Private Helpers

    private func resolveParkID() async throws {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "magicKingdomParkID"), !id.isEmpty {
            magicKingdomParkID = id
            return
        }

        let destinations = try await ThemeParksAPI.fetchDestinations()
        guard let wdw = destinations.destinations.first(where: { $0.slug == "waltdisneyworldresort" }) else {
            throw APIError.invalidResponse
        }
        guard let mk = wdw.parks.first(where: { $0.name.contains("Magic Kingdom") }) else {
            throw APIError.invalidResponse
        }

        magicKingdomParkID = mk.id
        defaults.set(magicKingdomParkID, forKey: "magicKingdomParkID")
    }

    private func processLiveData(_ response: EntityLiveDataResponse, saveToCache: Bool = true) {
        if saveToCache {
            CachedParkData.save(response)
        }

        // SHOW entities that have (or have ever had) a standby queue are character
        // meet-and-greets. Promote them to attractions so they appear in the attractions tab.
        let fetchedAttractions = response.liveData.filter { entity in
            entity.entityType == "ATTRACTION" ||
            (entity.entityType == "SHOW" &&
                (entity.queue?.standby != nil || knownQueueAttractionIDs.contains(entity.id)))
        }
        let fetchedShows = response.liveData.filter { entity in
            entity.entityType == "SHOW" &&
            entity.queue?.standby == nil &&
            !knownQueueAttractionIDs.contains(entity.id)
        }

        let now = Date()
        var queueIDsChanged = false

        var newReadings: [(id: String, waitTime: Int)] = []

        for entity in fetchedAttractions {
            if entity.queue != nil {
                if knownQueueAttractionIDs.insert(entity.id).inserted {
                    queueIDsChanged = true
                }
            }
            if let waitTime = entity.queue?.standby?.waitTime {
                var history = waitTimeHistory[entity.id] ?? []
                history.append(WaitTimeRecord(date: now, waitTime: waitTime))
                if history.count > PersistedWaitHistory.maxRecordsPerAttraction {
                    history = Array(history.suffix(PersistedWaitHistory.maxRecordsPerAttraction))
                }
                waitTimeHistory[entity.id] = history
                newReadings.append((entity.id, waitTime))
            }
        }

        // Persist new data points so background tasks and future sessions can see them.
        PersistedWaitHistory.appendBatch(newReadings, at: now)

        if queueIDsChanged {
            UserDefaults.standard.set(Array(knownQueueAttractionIDs), forKey: "knownQueueAttractionIDs")
        }

        attractions = fetchedAttractions
        shows = fetchedShows
    }

    private func processSchedule(_ response: EntityScheduleResponse) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        schedule = response.schedule.first { entry in
            entry.date == today && entry.type == "OPERATING"
        }
    }
}

