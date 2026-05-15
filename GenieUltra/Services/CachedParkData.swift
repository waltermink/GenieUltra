import Foundation

/// Persists the most recent live data response. Uses the App Group suite so the
/// widget extension can read it. Falls back to UserDefaults.standard if the App
/// Group entitlement hasn't been enabled yet.
enum CachedParkData {
    static let appGroupID = "group.com.genieultra"
    static let responseKey  = "cachedLiveDataResponse"
    static let timestampKey = "cachedLiveDataTimestamp"
    /// Key for the ordered list of attraction IDs the user wants shown in the widget.
    static let widgetAttractionIDsKey = "widgetAttractionIDs"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ response: EntityLiveDataResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        defaults.set(data, forKey: responseKey)
        defaults.set(Date(), forKey: timestampKey)
    }

    static func load() -> EntityLiveDataResponse? {
        guard let data = defaults.data(forKey: responseKey) else { return nil }
        return try? JSONDecoder().decode(EntityLiveDataResponse.self, from: data)
    }

    static var lastSaved: Date? {
        defaults.object(forKey: timestampKey) as? Date
    }

    // MARK: - Widget Attraction Selection

    static var widgetAttractionIDs: [String] {
        get { defaults.stringArray(forKey: widgetAttractionIDsKey) ?? [] }
        set { defaults.set(newValue, forKey: widgetAttractionIDsKey) }
    }
}
