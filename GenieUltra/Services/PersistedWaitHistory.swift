import Foundation

/// Persists wait-time history across app launches and background task executions.
///
/// Background tasks (BGAppRefreshTask) run in the main app process and can write
/// here directly. On next foreground, ParkDataStore merges this into its in-memory
/// waitTimeHistory so the graphs reflect all collected data.
///
/// Storage: UserDefaults.standard — nonisolated, safe to call from any context.
enum PersistedWaitHistory {

    private static let storageKey = "persistedWaitHistory"
    static let maxRecordsPerAttraction = 500

    // MARK: - Write

    /// Append a batch of (attractionID, waitTime) readings recorded at the same instant.
    /// Performs a single read-modify-write cycle for efficiency.
    static func appendBatch(_ readings: [(id: String, waitTime: Int)], at date: Date = Date()) {
        guard !readings.isEmpty else { return }
        var all = load()
        for (id, waitTime) in readings {
            var records = all[id] ?? []
            records.append(WaitTimeRecord(date: date, waitTime: waitTime))
            if records.count > maxRecordsPerAttraction {
                records = Array(records.suffix(maxRecordsPerAttraction))
            }
            all[id] = records
        }
        persist(all)
    }

    // MARK: - Read

    static func load() -> [String: [WaitTimeRecord]] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [WaitTimeRecord]].self, from: data)) ?? [:]
    }

    // MARK: - Private

    private static func persist(_ history: [String: [WaitTimeRecord]]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
