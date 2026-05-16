import ActivityKit
import Foundation

@MainActor
@Observable
final class LiveActivityManager {

    var isActive = false
    var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var activity: Activity<WaitTimeActivityAttributes>?

    // MARK: - Lifecycle

    func startMonitoring(attractions: [EntityLiveData]) {
        guard isSupported else { return }
        guard activity == nil else {
            // Already running — just push fresh state.
            Task { await update(with: attractions) }
            return
        }

        let monitoredIDs = Self.monitoredIDs()
        let tracked = attractions.filter { monitoredIDs.contains($0.id) }
        guard !tracked.isEmpty else { return }

        let attrs = WaitTimeActivityAttributes(parkName: "Magic Kingdom")
        let state = WaitTimeActivityAttributes.ContentState(
            snapshots: tracked.map { AttractionSnapshot(from: $0) },
            lastUpdated: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date(timeIntervalSinceNow: 20 * 60)
        )

        do {
            activity = try Activity.request(
                attributes: attrs,
                content: content,
                pushType: nil   // set to .token here when wiring up APNS push support
            )
            isActive = true
        } catch {
            // Silently swallow — activity permissions not granted or Live Activities disabled.
        }
    }

    func update(with attractions: [EntityLiveData]) async {
        guard let activity else { return }

        let monitoredIDs = Self.monitoredIDs()
        let tracked = attractions.filter { monitoredIDs.contains($0.id) }

        let state = WaitTimeActivityAttributes.ContentState(
            snapshots: tracked.map { AttractionSnapshot(from: $0) },
            lastUpdated: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date(timeIntervalSinceNow: 20 * 60)
        )
        await activity.update(content)
    }

    func stopMonitoring() async {
        let dismissal = ActivityUIDismissalPolicy.immediate
        await activity?.end(nil, dismissalPolicy: dismissal)
        activity = nil
        isActive = false
    }

    // MARK: - Background Update (called from BackgroundRefreshManager — nonisolated context)

    /// Updates every active Live Activity using the freshly-fetched park data.
    /// Safe to call from a nonisolated async context (BGAppRefreshTask).
    nonisolated static func backgroundUpdate(with entities: [EntityLiveData]) async {
        let monitoredIDs = monitoredIDs()
        let tracked = entities.filter { monitoredIDs.contains($0.id) }
        guard !tracked.isEmpty else { return }

        let state = WaitTimeActivityAttributes.ContentState(
            snapshots: tracked.map { AttractionSnapshot(from: $0) },
            lastUpdated: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date(timeIntervalSinceNow: 20 * 60)
        )
        for act in Activity<WaitTimeActivityAttributes>.activities {
            await act.update(content)
        }
    }

    // MARK: - Private

    nonisolated private static func monitoredIDs() -> Set<String> {
        AlertStore.monitoredWaitAttractionIDs()
            .union(AlertStore.monitoredLLAttractionIDs())
    }
}

// MARK: - AttractionSnapshot convenience init (main-app only)

extension AttractionSnapshot {
    init(from entity: EntityLiveData) {
        id             = entity.id
        name           = entity.name
        status         = entity.status ?? "CLOSED"
        waitMinutes    = entity.queue?.standby?.waitTime
        llState        = entity.queue?.returnTime?.state
        llReturnStart  = entity.queue?.returnTime?.returnStart
        paState        = entity.queue?.paidReturnTime?.state
        paReturnStart  = entity.queue?.paidReturnTime?.returnStart
    }
}
