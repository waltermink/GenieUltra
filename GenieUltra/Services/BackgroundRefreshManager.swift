import BackgroundTasks
import Foundation

enum BackgroundRefreshManager {

    // MARK: - Task Identifiers

    /// Full park sweep — all entities, all alerts, widget cache update.
    static let taskIdentifier         = "com.genieultra.parkrefresh"
    /// Targeted wait-time poll — only monitored attractions; persists history + checks wait alerts.
    static let targetedWaitIdentifier = "com.genieultra.targeted.waittime"
    /// Targeted Lightning Lane poll — only checks LL alerts; most time-sensitive signal.
    static let targetedLLIdentifier   = "com.genieultra.targeted.ll"

    // MARK: - UserDefaults Keys

    static let intervalKey            = "backgroundPollingInterval"
    static let enabledKey             = "backgroundPollingEnabled"

    static let targetedWaitIntervalKey = "targetedWaitPollingInterval"
    static let targetedWaitEnabledKey  = "targetedWaitPollingEnabled"

    static let targetedLLIntervalKey   = "targetedLLPollingInterval"
    static let targetedLLEnabledKey    = "targetedLLPollingEnabled"

    // MARK: - Interval Bounds

    /// Bounds for the full-sweep interval.
    static let minimumInterval: TimeInterval = 30
    static let maximumInterval: TimeInterval = 60 * 60

    /// Bounds for targeted-task intervals.
    static let targetedMinInterval: TimeInterval = 30
    static let targetedMaxInterval: TimeInterval = 30 * 60

    // MARK: - Computed Settings

    static var currentInterval: TimeInterval {
        clamp(UserDefaults.standard.double(forKey: intervalKey),
              min: minimumInterval, max: maximumInterval, default: minimumInterval)
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var targetedWaitInterval: TimeInterval {
        clamp(UserDefaults.standard.double(forKey: targetedWaitIntervalKey),
              min: targetedMinInterval, max: targetedMaxInterval, default: 5 * 60)
    }

    static var isTargetedWaitEnabled: Bool {
        UserDefaults.standard.object(forKey: targetedWaitEnabledKey) as? Bool ?? true
    }

    static var targetedLLInterval: TimeInterval {
        clamp(UserDefaults.standard.double(forKey: targetedLLIntervalKey),
              min: targetedMinInterval, max: targetedMaxInterval, default: 3 * 60)
    }

    static var isTargetedLLEnabled: Bool {
        UserDefaults.standard.object(forKey: targetedLLEnabledKey) as? Bool ?? true
    }

    // MARK: - Scheduling

    static func scheduleNextRefresh() {
        guard isEnabled else { return }
        submit(taskIdentifier, after: currentInterval)
    }

    static func scheduleTargetedWaitRefresh() {
        guard isTargetedWaitEnabled else { return }
        submit(targetedWaitIdentifier, after: targetedWaitInterval)
    }

    static func scheduleTargetedLLRefresh() {
        guard isTargetedLLEnabled else { return }
        submit(targetedLLIdentifier, after: targetedLLInterval)
    }

    /// Reschedule all enabled background tasks at once — call when entering background.
    static func scheduleAll() {
        scheduleNextRefresh()
        scheduleTargetedWaitRefresh()
        scheduleTargetedLLRefresh()
    }

    // MARK: - Background Task Execution

    /// Full park sweep.
    /// - Updates the widget cache (triggers widget reload).
    /// - Persists wait-time history for every attraction with a live wait time.
    /// - Checks all active alerts (wait + LL).
    static func performBackgroundFetch() async {
        scheduleNextRefresh()

        guard let parkID = resolvedParkID() else { return }
        guard let response = try? await ThemeParksAPI.fetchEntityLiveData(entityID: parkID) else { return }

        CachedParkData.save(response)
        persistHistory(from: response.liveData, filter: nil)

        if AlertStore.hasActiveAlertsInStorage() {
            await AlertStore.backgroundCheck(against: response.liveData)
        }
    }

    /// Targeted wait-time poll.
    /// - Fetches the same park endpoint but only persists history for monitored attractions.
    /// - Checks wait-time alerts only (skips LL evaluation to keep it fast).
    static func performTargetedWaitFetch() async {
        scheduleTargetedWaitRefresh()

        let monitoredIDs = AlertStore.monitoredWaitAttractionIDs()
        guard !monitoredIDs.isEmpty else { return }
        guard let parkID = resolvedParkID() else { return }
        guard let response = try? await ThemeParksAPI.fetchEntityLiveData(entityID: parkID) else { return }

        persistHistory(from: response.liveData, filter: monitoredIDs)

        if AlertStore.hasActiveWaitAlertsInStorage() {
            await AlertStore.backgroundCheckWaitAlerts(entities: response.liveData)
        }
    }

    /// Targeted Lightning Lane poll.
    /// - Most frequent of the three tasks since LL availability is time-critical.
    /// - Only evaluates LL alerts; does not persist wait-time history.
    static func performTargetedLLFetch() async {
        scheduleTargetedLLRefresh()

        guard AlertStore.hasActiveLLAlertsInStorage() else { return }
        guard let parkID = resolvedParkID() else { return }
        guard let response = try? await ThemeParksAPI.fetchEntityLiveData(entityID: parkID) else { return }

        await AlertStore.backgroundCheckLLAlerts(entities: response.liveData)
    }

    // MARK: - Private Helpers

    private static func resolvedParkID() -> String? {
        guard let id = UserDefaults.standard.string(forKey: "magicKingdomParkID"), !id.isEmpty else { return nil }
        return id
    }

    private static func persistHistory(from entities: [EntityLiveData], filter: Set<String>?) {
        let readings: [(id: String, waitTime: Int)] = entities.compactMap { entity in
            if let filter, !filter.contains(entity.id) { return nil }
            guard let wait = entity.queue?.standby?.waitTime else { return nil }
            return (entity.id, wait)
        }
        PersistedWaitHistory.appendBatch(readings)
    }

    private static func submit(_ identifier: String, after interval: TimeInterval) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func clamp(_ value: Double, min: TimeInterval, max: TimeInterval, default fallback: TimeInterval) -> TimeInterval {
        guard value >= min else { return fallback }
        return Swift.min(value, max)
    }
}
