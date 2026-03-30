import SwiftUI

@main
struct GenieUltraApp: App {
    @State private var store = ParkDataStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(store)
        }
    }
}

