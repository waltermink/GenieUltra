import Foundation

struct EntityLiveDataResponse: Codable {
    let liveData: [EntityLiveData]
}

struct EntityLiveData: Codable, Identifiable {
    let id: String
    let name: String
    let entityType: String
    let status: String?
    let lastUpdated: String?
    let queue: QueueData?
    let showtimes: [ShowTime]?
}

struct QueueData: Codable {
    let standby: StandbyQueue?
    let returnTime: ReturnTimeQueue?
    let paidReturnTime: ReturnTimeQueue?

    enum CodingKeys: String, CodingKey {
        case standby = "STANDBY"
        case returnTime = "RETURN_TIME"
        case paidReturnTime = "PAID_RETURN_TIME"
    }
}

struct StandbyQueue: Codable {
    let waitTime: Int?
}

struct ReturnTimeQueue: Codable {
    let state: String?
    let returnStart: String?
    let returnEnd: String?
}

struct ShowTime: Codable, Identifiable {
    let type: String?
    let startTime: String?
    let endTime: String?

    var id: String { "\(type ?? "")-\(startTime ?? "")-\(endTime ?? "")" }
}

struct WaitTimeRecord: Identifiable {
    let id = UUID()
    let date: Date
    let waitTime: Int
}
