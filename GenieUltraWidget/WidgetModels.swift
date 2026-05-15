import Foundation
import WidgetKit

// Lightweight model decoded directly from the App Group cache.
// Duplicated here because widget extensions can't import the main app module.

struct WidgetLiveDataResponse: Codable {
    let liveData: [WidgetEntity]
}

struct WidgetEntity: Codable, Identifiable {
    let id: String
    let name: String
    let status: String?
    let queue: WidgetQueueData?
}

struct WidgetQueueData: Codable {
    let standby: WidgetStandby?
    let returnTime: WidgetReturnTime?
    let paidReturnTime: WidgetReturnTime?

    enum CodingKeys: String, CodingKey {
        case standby = "STANDBY"
        case returnTime = "RETURN_TIME"
        case paidReturnTime = "PAID_RETURN_TIME"
    }
}

struct WidgetStandby: Codable { let waitTime: Int? }

struct WidgetReturnTime: Codable {
    let state: String?
    let returnStart: String?
}

// MARK: - Timeline Entry

struct WaitTimesEntry: TimelineEntry {
    let date: Date
    let attractions: [WidgetEntity]
    let lastUpdated: Date?

    static let placeholder = WaitTimesEntry(
        date: Date(),
        attractions: [
            WidgetEntity(id: "1", name: "Space Mountain", status: "OPERATING",
                         queue: WidgetQueueData(
                             standby: WidgetStandby(waitTime: 45),
                             returnTime: WidgetReturnTime(state: "AVAILABLE", returnStart: nil),
                             paidReturnTime: nil)),
            WidgetEntity(id: "2", name: "Seven Dwarfs Mine Train", status: "OPERATING",
                         queue: WidgetQueueData(
                             standby: WidgetStandby(waitTime: 90),
                             returnTime: nil,
                             paidReturnTime: nil)),
            WidgetEntity(id: "3", name: "Haunted Mansion", status: "OPERATING",
                         queue: WidgetQueueData(
                             standby: WidgetStandby(waitTime: 20),
                             returnTime: nil,
                             paidReturnTime: nil)),
            WidgetEntity(id: "4", name: "Big Thunder Mountain", status: "DOWN",
                         queue: nil),
        ],
        lastUpdated: Date()
    )
}

// MARK: - Shared Keys

enum WidgetSharedKeys {
    static let appGroupID           = "group.com.genieultra"
    static let liveDataKey          = "cachedLiveDataResponse"
    static let timestampKey         = "cachedLiveDataTimestamp"
    static let widgetAttractionIDs  = "widgetAttractionIDs"
}
