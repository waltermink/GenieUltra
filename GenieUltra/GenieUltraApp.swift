import SwiftUI
import UserNotifications

@main
struct GenieUltraApp: App {
    @State private var store = ParkDataStore()
    @State private var alertStore = AlertStore()
    @State private var liveActivityManager = LiveActivityManager()
    @State private var pushServer = PushServerClient()

    // Retained for the lifetime of the app — UNUserNotificationCenter holds a weak reference.
    private let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        // Without this delegate iOS silently drops notifications while the app is in the foreground.
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(store)
                .environment(alertStore)
                .environment(liveActivityManager)
                .environment(pushServer)
                .task {
                    // AlertStore.save() writes to UserDefaults first, THEN fires
                    // this callback, so by the time syncAlerts() reads from
                    // UserDefaults it sees the up-to-date config. Capturing only
                    // pushServer avoids the alertStore → closure → alertStore
                    // retain cycle (alertStore owns the callback).
                    alertStore.onAlertsChanged = { [pushServer] in
                        Task { await pushServer.syncAlerts() }
                    }
                    // Initial sync on launch covers the app-killed-then-reopened
                    // case where alerts changed since the last sync.
                    await pushServer.syncAlerts()
                }
        }
    }
}

// MARK: - Foreground Notification Delegate

/// Tells iOS to display the banner, play the sound, and update the badge
/// even while the app is in the foreground (the default is to suppress all three).
private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
