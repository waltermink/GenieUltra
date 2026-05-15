import Foundation

/// Persists the most recent live data response so it can be shared between the
/// foreground app, background refreshes, and (eventually) widget extensions via App Groups.
enum CachedParkData {
    // NOTE: When adding widget targets, change both keys to use
    // UserDefaults(suiteName: "group.com.genieultra") for cross-process sharing.
    private static let responseKey = "cachedLiveDataResponse"
    private static let timestampKey = "cachedLiveDataTimestamp"

    static func save(_ response: EntityLiveDataResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: responseKey)
        UserDefaults.standard.set(Date(), forKey: timestampKey)
    }

    static func load() -> EntityLiveDataResponse? {
        guard let data = UserDefaults.standard.data(forKey: responseKey) else { return nil }
        return try? JSONDecoder().decode(EntityLiveDataResponse.self, from: data)
    }

    static var lastSaved: Date? {
        UserDefaults.standard.object(forKey: timestampKey) as? Date
    }
}
