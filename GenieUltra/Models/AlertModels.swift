import Foundation

enum WaitTimeAlertType: String, Codable, CaseIterable {
    case threshold   // notify when wait drops to or below the threshold
    case isOperating // notify when the ride starts reporting any wait time
}

struct WaitTimeAlert: Identifiable, Codable {
    var id: UUID = UUID()
    var attractionID: String
    var attractionName: String
    var type: WaitTimeAlertType
    var threshold: Int?     // minutes; only used when type == .threshold
    var enabled: Bool = true
    var lastFired: Date?
}

struct LightningLaneAlert: Identifiable, Codable {
    var id: UUID = UUID()
    var attractionID: String
    var attractionName: String
    var includeStandardLL: Bool = true      // standard Lightning Lane (returnTime queue)
    var includePremierAccess: Bool = true   // Premier Access / paid LL (paidReturnTime queue)
    var windowStartHour: Int = 10           // only notify if returnStart hour >= this
    var windowEndHour: Int = 18             // only notify if returnStart hour <= this
    var enabled: Bool = true
    var lastFiredReturnStart: String?       // deduplication: don't re-fire for same return window
}
