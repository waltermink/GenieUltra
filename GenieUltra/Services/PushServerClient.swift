import Foundation

/// Bridges the app to the Cloudflare Worker that polls themeparks.wiki and
/// fires notifications via ntfy.sh (and/or Telegram). No device tokens, no
/// Apple Developer Program required — the Worker pushes via channels that
/// already have their own iOS apps doing APNS delivery.
///
/// Lifecycle:
///   1. On launch the app reads the saved server URL + shared secret from
///      UserDefaults and calls `syncAlerts()` to push the current alert config.
///   2. Whenever AlertStore.save() runs (alerts added / edited / toggled /
///      deleted), the App's onAlertsChanged callback calls `syncAlerts()`.
///   3. Settings has a "Send test push" button which calls the Worker's /test
///      endpoint and shows the result.
@MainActor
@Observable
final class PushServerClient {

    // MARK: - Persistent settings

    static let serverURLKey    = "pushServerURL"
    static let sharedSecretKey = "pushServerSecret"
    static let lastSyncKey     = "pushServerLastSync"

    // MARK: - Observable UI state

    enum Status: Equatable {
        case notConfigured
        case syncing
        case connected(lastSync: Date)
        case error(String)
    }

    var status: Status = .notConfigured
    var lastError: String?

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: Self.serverURLKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.serverURLKey)
            recomputeStatus()
        }
    }

    var sharedSecret: String {
        get { UserDefaults.standard.string(forKey: Self.sharedSecretKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.sharedSecretKey)
            recomputeStatus()
        }
    }

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !sharedSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() { recomputeStatus() }

    // MARK: - Operations

    /// Pushes current alert config to the Worker. Safe to call repeatedly.
    /// Reads alerts from UserDefaults so it works equally well from foreground
    /// or as a callback after AlertStore.save() (which writes to UserDefaults first).
    func syncAlerts() async {
        guard isConfigured else { recomputeStatus(); return }
        status = .syncing
        do {
            let payload = currentPayload()
            try await post(path: "/sync-alerts", body: payload)
            let now = Date()
            UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
            status = .connected(lastSync: now)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .error(error.localizedDescription)
        }
    }

    /// Asks the Worker to fire a test notification through every configured channel.
    func fireServerTest() async throws {
        guard isConfigured else { throw PushServerError.notConfigured }
        let emptyBody: [String: Any] = [:]
        try await post(path: "/test", body: emptyBody)
    }

    /// Unauthenticated health check — verifies URL + that the Worker is reachable.
    /// Returns the Worker's parsed health-response body for display.
    func pingHealth() async throws -> String {
        guard let url = makeURL(path: "/health") else { throw PushServerError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw PushServerError.invalidResponse }
        guard http.statusCode == 200 else { throw PushServerError.httpStatus(http.statusCode) }
        return String(data: data, encoding: .utf8) ?? "(empty)"
    }

    // MARK: - Private

    private func currentPayload() -> [String: Any] {
        // Read alerts from UserDefaults directly so this works regardless of
        // whether AlertStore is currently in memory (it always is on iOS since
        // we have a single process, but reading from UserDefaults makes this
        // independent of injection and matches AlertStore's persistence keys).
        let waits = (try? JSONDecoder().decode(
            [WaitTimeAlert].self,
            from: UserDefaults.standard.data(forKey: "waitTimeAlerts") ?? Data()
        )) ?? []
        let lls = (try? JSONDecoder().decode(
            [LightningLaneAlert].self,
            from: UserDefaults.standard.data(forKey: "lightningLaneAlerts") ?? Data()
        )) ?? []

        let waitPayload: [[String: Any]] = waits.filter(\.enabled).map { a in
            var item: [String: Any] = [
                "attractionID":   a.attractionID,
                "attractionName": a.attractionName,
                "type":           a.type.rawValue,
            ]
            if let t = a.threshold { item["threshold"] = t }
            return item
        }
        let llPayload: [[String: Any]] = lls.filter(\.enabled).map { a in [
            "attractionID":         a.attractionID,
            "attractionName":       a.attractionName,
            "includeStandardLL":    a.includeStandardLL,
            "includePremierAccess": a.includePremierAccess,
            "windowStartHour":      a.windowStartHour,
            "windowEndHour":        a.windowEndHour,
        ]}

        return ["waitAlerts": waitPayload, "llAlerts": llPayload]
    }

    private func post(path: String, body: [String: Any]) async throws {
        guard let url = makeURL(path: path) else { throw PushServerError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(sharedSecret.trimmingCharacters(in: .whitespaces))",
                     forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw PushServerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? ""
            throw PushServerError.httpStatusWithBody(http.statusCode, payload)
        }
    }

    /// Builds a request URL by joining the user-entered base with the path.
    /// Strips trailing slashes from the base so we never end up with `//path`.
    private func makeURL(path: String) -> URL? {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    private func recomputeStatus() {
        if !isConfigured {
            status = .notConfigured
        } else if let last = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date {
            status = .connected(lastSync: last)
        }
        // else: leave whatever status we have (likely we'll re-sync soon and update)
    }
}

// MARK: - Errors

enum PushServerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case httpStatusWithBody(Int, String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:                       return "Invalid server URL"
        case .invalidResponse:                  return "Bad response from server"
        case .httpStatus(let s):                return "Server returned \(s)"
        case .httpStatusWithBody(let s, let b): return "Server returned \(s): \(b)"
        case .notConfigured:                    return "Push server is not configured"
        }
    }
}
