import Foundation
import UserNotifications

// File-scope constants — accessible from both @MainActor and nonisolated contexts
// without triggering Swift 6 actor-isolation errors.
private enum AlertKeys {
    static let waitAlerts = "waitTimeAlerts"
    static let llAlerts   = "lightningLaneAlerts"
    static let cooldown: TimeInterval = 3600   // min interval between repeat wait-alert fires
}

@MainActor
@Observable
class AlertStore {
    var waitTimeAlerts: [WaitTimeAlert] = []
    var lightningLaneAlerts: [LightningLaneAlert] = []

    init() { load() }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(waitTimeAlerts) {
            UserDefaults.standard.set(data, forKey: AlertKeys.waitAlerts)
        }
        if let data = try? JSONEncoder().encode(lightningLaneAlerts) {
            UserDefaults.standard.set(data, forKey: AlertKeys.llAlerts)
        }
    }

    func reload() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: AlertKeys.waitAlerts),
           let decoded = try? JSONDecoder().decode([WaitTimeAlert].self, from: data) {
            waitTimeAlerts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: AlertKeys.llAlerts),
           let decoded = try? JSONDecoder().decode([LightningLaneAlert].self, from: data) {
            lightningLaneAlerts = decoded
        }
    }

    // MARK: - CRUD

    func addWaitAlert(_ alert: WaitTimeAlert) { waitTimeAlerts.append(alert); save() }
    func addLLAlert(_ alert: LightningLaneAlert) { lightningLaneAlerts.append(alert); save() }

    func updateWaitAlert(_ alert: WaitTimeAlert) {
        guard let idx = waitTimeAlerts.firstIndex(where: { $0.id == alert.id }) else { return }
        waitTimeAlerts[idx] = alert; save()
    }
    func updateLLAlert(_ alert: LightningLaneAlert) {
        guard let idx = lightningLaneAlerts.firstIndex(where: { $0.id == alert.id }) else { return }
        lightningLaneAlerts[idx] = alert; save()
    }

    func deleteWaitAlert(id: UUID) { waitTimeAlerts.removeAll { $0.id == id }; save() }
    func deleteLLAlert(id: UUID) { lightningLaneAlerts.removeAll { $0.id == id }; save() }

    func toggleWaitAlert(id: UUID) {
        guard let idx = waitTimeAlerts.firstIndex(where: { $0.id == id }) else { return }
        waitTimeAlerts[idx].enabled.toggle()
        save()
    }

    func toggleLLAlert(id: UUID) {
        guard let idx = lightningLaneAlerts.firstIndex(where: { $0.id == id }) else { return }
        lightningLaneAlerts[idx].enabled.toggle()
        save()
    }

    var hasActiveAlerts: Bool {
        waitTimeAlerts.contains { $0.enabled } || lightningLaneAlerts.contains { $0.enabled }
    }

    // MARK: - Foreground Alert Checking (in-memory, main actor)

    func checkAlerts(against attractions: [EntityLiveData]) async {
        let now = Date()
        for i in waitTimeAlerts.indices where waitTimeAlerts[i].enabled {
            let alert = waitTimeAlerts[i]
            guard let attraction = attractions.first(where: { $0.id == alert.attractionID }) else { continue }
            if let lastFired = alert.lastFired, now.timeIntervalSince(lastFired) < AlertKeys.cooldown { continue }

            switch alert.type {
            case .threshold:
                guard let threshold = alert.threshold,
                      let currentWait = attraction.queue?.standby?.waitTime,
                      currentWait <= threshold else { continue }
                await NotificationManager.send(
                    title: "Wait time is low: \(attraction.name)",
                    body: "Current wait: \(currentWait) min (your threshold: ≤\(threshold) min)",
                    identifier: "wait-threshold-\(alert.id)"
                )
                waitTimeAlerts[i].lastFired = now

            case .isOperating:
                guard attraction.status == "OPERATING",
                      attraction.queue?.standby?.waitTime != nil else { continue }
                let waitStr = attraction.queue?.standby?.waitTime.map { "\($0) min" } ?? "open"
                await NotificationManager.send(
                    title: "\(attraction.name) is now operating",
                    body: "Current wait: \(waitStr)",
                    identifier: "wait-operating-\(alert.id)"
                )
                waitTimeAlerts[i].lastFired = now
            }
        }

        let calendar = Calendar.current
        for i in lightningLaneAlerts.indices where lightningLaneAlerts[i].enabled {
            let alert = lightningLaneAlerts[i]
            guard let attraction = attractions.first(where: { $0.id == alert.attractionID }) else { continue }

            var fired = false

            if alert.includeStandardLL,
               let rt = attraction.queue?.returnTime,
               rt.state == "AVAILABLE",
               let returnStart = rt.returnStart,
               returnStart != alert.lastFiredReturnStart,
               Self.isWithinWindow(returnStart, startHour: alert.windowStartHour, endHour: alert.windowEndHour, calendar: calendar) {
                await NotificationManager.send(
                    title: "Lightning Lane available: \(attraction.name)",
                    body: "Return time: \(TimeFormatter.formatTime(returnStart))",
                    identifier: "ll-standard-\(alert.id)"
                )
                lightningLaneAlerts[i].lastFiredReturnStart = returnStart
                fired = true
            }

            if !fired,
               alert.includePremierAccess,
               let rt = attraction.queue?.paidReturnTime,
               rt.state == "AVAILABLE",
               let returnStart = rt.returnStart,
               returnStart != alert.lastFiredReturnStart,
               Self.isWithinWindow(returnStart, startHour: alert.windowStartHour, endHour: alert.windowEndHour, calendar: calendar) {
                await NotificationManager.send(
                    title: "Lightning Lane+ available: \(attraction.name)",
                    body: "Return time: \(TimeFormatter.formatTime(returnStart))",
                    identifier: "ll-paid-\(alert.id)"
                )
                lightningLaneAlerts[i].lastFiredReturnStart = returnStart
            }
        }

        save()
    }

    // MARK: - Test Fire (ignores cooldown and conditions — for development use)

    func fireTest(waitAlert alert: WaitTimeAlert) async {
        let body: String
        switch alert.type {
        case .threshold:
            body = "Test: wait would be at or below \(alert.threshold ?? 0) min"
        case .isOperating:
            body = "Test: ride would be reporting an active wait time"
        }
        await NotificationManager.send(
            title: "[TEST] \(alert.attractionName)",
            body: body,
            identifier: "test-wait-\(alert.id)-\(Date().timeIntervalSince1970)"
        )
    }

    func fireTest(llAlert alert: LightningLaneAlert) async {
        let llType = alert.includeStandardLL ? "Lightning Lane" : "Premier Access"
        await NotificationManager.send(
            title: "[TEST] \(llType) available: \(alert.attractionName)",
            body: "Test: return time would be within your \(hourLabel(alert.windowStartHour))–\(hourLabel(alert.windowEndHour)) window",
            identifier: "test-ll-\(alert.id)-\(Date().timeIntervalSince1970)"
        )
    }

    /// Fires test notifications for every enabled alert regardless of conditions or cooldown.
    func fireAllTests() async {
        for alert in waitTimeAlerts where alert.enabled {
            await fireTest(waitAlert: alert)
        }
        for alert in lightningLaneAlerts where alert.enabled {
            await fireTest(llAlert: alert)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        guard let d = Calendar.current.date(from: c) else { return "\(hour):00" }
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: d)
    }

    // MARK: - Background Alert Checking (nonisolated static — safe to call from BGAppRefreshTask)

    nonisolated static func hasActiveAlertsInStorage() -> Bool {
        hasActiveWaitAlertsInStorage() || hasActiveLLAlertsInStorage()
    }

    nonisolated static func hasActiveWaitAlertsInStorage() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: AlertKeys.waitAlerts),
              let alerts = try? JSONDecoder().decode([WaitTimeAlert].self, from: data) else { return false }
        return alerts.contains { $0.enabled }
    }

    nonisolated static func hasActiveLLAlertsInStorage() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: AlertKeys.llAlerts),
              let alerts = try? JSONDecoder().decode([LightningLaneAlert].self, from: data) else { return false }
        return alerts.contains { $0.enabled }
    }

    /// Attraction IDs from every enabled wait-time alert.
    nonisolated static func monitoredWaitAttractionIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: AlertKeys.waitAlerts),
              let alerts = try? JSONDecoder().decode([WaitTimeAlert].self, from: data) else { return [] }
        return Set(alerts.filter { $0.enabled }.map { $0.attractionID })
    }

    /// Attraction IDs from every enabled Lightning Lane alert.
    nonisolated static func monitoredLLAttractionIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: AlertKeys.llAlerts),
              let alerts = try? JSONDecoder().decode([LightningLaneAlert].self, from: data) else { return [] }
        return Set(alerts.filter { $0.enabled }.map { $0.attractionID })
    }

    nonisolated static func backgroundCheck(against entities: [EntityLiveData]) async {
        await backgroundCheckWaitAlerts(entities: entities)
        await backgroundCheckLLAlerts(entities: entities)
    }

    nonisolated static func backgroundCheckWaitAlerts(entities: [EntityLiveData]) async {
        guard let data = UserDefaults.standard.data(forKey: AlertKeys.waitAlerts),
              var alerts = try? JSONDecoder().decode([WaitTimeAlert].self, from: data) else { return }

        var changed = false
        let now = Date()

        for i in alerts.indices where alerts[i].enabled {
            let alert = alerts[i]
            guard let attraction = entities.first(where: { $0.id == alert.attractionID }) else { continue }
            if let lastFired = alert.lastFired, now.timeIntervalSince(lastFired) < AlertKeys.cooldown { continue }

            switch alert.type {
            case .threshold:
                guard let threshold = alert.threshold,
                      let currentWait = attraction.queue?.standby?.waitTime,
                      currentWait <= threshold else { continue }
                await NotificationManager.send(
                    title: "Wait time is low: \(attraction.name)",
                    body: "Current wait: \(currentWait) min (threshold: ≤\(threshold) min)",
                    identifier: "bg-wait-threshold-\(alert.id)"
                )
                alerts[i].lastFired = now
                changed = true

            case .isOperating:
                guard attraction.status == "OPERATING",
                      attraction.queue?.standby?.waitTime != nil else { continue }
                let waitStr = attraction.queue?.standby?.waitTime.map { "\($0) min" } ?? "open"
                await NotificationManager.send(
                    title: "\(attraction.name) is now operating",
                    body: "Current wait: \(waitStr)",
                    identifier: "bg-wait-operating-\(alert.id)"
                )
                alerts[i].lastFired = now
                changed = true
            }
        }

        if changed, let encoded = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(encoded, forKey: AlertKeys.waitAlerts)
        }
    }

    nonisolated static func backgroundCheckLLAlerts(entities: [EntityLiveData]) async {
        guard let data = UserDefaults.standard.data(forKey: AlertKeys.llAlerts),
              var alerts = try? JSONDecoder().decode([LightningLaneAlert].self, from: data) else { return }

        var changed = false
        let calendar = Calendar.current

        for i in alerts.indices where alerts[i].enabled {
            let alert = alerts[i]
            guard let attraction = entities.first(where: { $0.id == alert.attractionID }) else { continue }

            var fired = false

            if alert.includeStandardLL,
               let rt = attraction.queue?.returnTime,
               rt.state == "AVAILABLE",
               let returnStart = rt.returnStart,
               returnStart != alert.lastFiredReturnStart,
               isWithinWindow(returnStart, startHour: alert.windowStartHour, endHour: alert.windowEndHour, calendar: calendar) {
                await NotificationManager.send(
                    title: "Lightning Lane available: \(attraction.name)",
                    body: "Return time: \(formatReturnTime(returnStart))",
                    identifier: "bg-ll-standard-\(alert.id)"
                )
                alerts[i].lastFiredReturnStart = returnStart
                changed = true
                fired = true
            }

            if !fired,
               alert.includePremierAccess,
               let rt = attraction.queue?.paidReturnTime,
               rt.state == "AVAILABLE",
               let returnStart = rt.returnStart,
               returnStart != alert.lastFiredReturnStart,
               isWithinWindow(returnStart, startHour: alert.windowStartHour, endHour: alert.windowEndHour, calendar: calendar) {
                await NotificationManager.send(
                    title: "Lightning Lane+ available: \(attraction.name)",
                    body: "Return time: \(formatReturnTime(returnStart))",
                    identifier: "bg-ll-paid-\(alert.id)"
                )
                alerts[i].lastFiredReturnStart = returnStart
                changed = true
            }
        }

        if changed, let encoded = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(encoded, forKey: AlertKeys.llAlerts)
        }
    }

    // MARK: - Shared Utilities

    nonisolated static func isWithinWindow(_ timeString: String, startHour: Int, endHour: Int, calendar: Calendar) -> Bool {
        guard let date = parseReturnTime(timeString) else { return false }
        let hour = calendar.component(.hour, from: date)
        return hour >= startHour && hour <= endHour
    }

    nonisolated static func parseReturnTime(_ timeString: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: timeString) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: timeString) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: timeString)
    }

    // Creates local formatter instances — safe from nonisolated/background context.
    nonisolated private static func formatReturnTime(_ timeString: String) -> String {
        guard let date = parseReturnTime(timeString) else { return timeString }
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: date)
    }
}
