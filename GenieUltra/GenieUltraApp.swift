import SwiftUI
import UserNotifications

@main
struct GenieUltraApp: App {
    @State private var store = ParkDataStore()
    @State private var alertStore = AlertStore()

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
        }
        // Registers the BGAppRefreshTask handler automatically — no manual
        // BGTaskScheduler.register(...) call needed. Requires
        // BGTaskSchedulerPermittedIdentifiers in Info.plist containing
        // "com.genieultra.parkrefresh".
        .backgroundTask(.appRefresh(BackgroundRefreshManager.taskIdentifier)) {
            await BackgroundRefreshManager.performBackgroundFetch()
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
