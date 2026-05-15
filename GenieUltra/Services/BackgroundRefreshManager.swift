import BackgroundTasks
import Foundation

enum BackgroundRefreshManager {
    static let taskIdentifier = "com.genieultra.parkrefresh"

    static let intervalKey = "backgroundPollingInterval"
    static let enabledKey  = "backgroundPollingEnabled"

    // Minimum configurable interval is 1 minute; iOS enforces ~15 min in practice.
    static let minimumInterval: TimeInterval = 60
    static let maximumInterval: TimeInterval = 60 * 60

    static var currentInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: intervalKey)
        guard stored >= minimumInterval else { return minimumInterval }
        return min(stored, maximumInterval)
    }

    static var isEnabled: Bool {
        // Object-based read so we can distinguish "never set" from false.
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Request the next background wake. Skipped when background polling is disabled.
    static func scheduleNextRefresh() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: currentInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Fetch live data in the background, update the cache, and check active alerts.
    static func performBackgroundFetch() async {
        // Reschedule before doing work so the chain survives even if this fetch fails.
        scheduleNextRefresh()

        guard let parkID = UserDefaults.standard.string(forKey: "magicKingdomParkID"),
              !parkID.isEmpty else { return }

        guard let response = try? await ThemeParksAPI.fetchEntityLiveData(entityID: parkID) else { return }
        CachedParkData.save(response)

        // Only evaluate alert rules when there's at least one active alert —
        // avoids unnecessary work when the user hasn't configured any monitoring.
        if AlertStore.hasActiveAlertsInStorage() {
            await AlertStore.backgroundCheck(against: response.liveData)
        }
    }
}
