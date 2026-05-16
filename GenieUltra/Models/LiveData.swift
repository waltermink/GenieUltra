import Foundation

struct EntityLiveDataResponse: Codable {
    let liveData: [EntityLiveData]
}

struct EntityLiveData: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let entityType: String
    let status: String?
    let lastUpdated: String?
    let queue: QueueData?
    let showtimes: [ShowTime]?
    let forecast: [ForecastEntry]?
}

struct QueueData: Codable, Equatable {
    let standby: StandbyQueue?
    let returnTime: ReturnTimeQueue?
    let paidReturnTime: ReturnTimeQueue?

    enum CodingKeys: String, CodingKey {
        case standby = "STANDBY"
        case returnTime = "RETURN_TIME"
        case paidReturnTime = "PAID_RETURN_TIME"
    }
}

struct StandbyQueue: Codable, Equatable {
    let waitTime: Int?
}

struct ReturnTimeQueue: Codable, Equatable {
    let state: String?
    let returnStart: String?
    let returnEnd: String?
}

struct ShowTime: Codable, Identifiable, Equatable {
    let type: String?
    let startTime: String?
    let endTime: String?

    var id: String { "\(type ?? "")-\(startTime ?? "")-\(endTime ?? "")" }
}

struct ForecastEntry: Codable, Identifiable, Equatable {
    let time: String
    let waitTime: Int
    let percentage: Int

    var id: String { time }
}

struct WaitTimeRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let waitTime: Int

    init(date: Date, waitTime: Int) {
        self.id = UUID()
        self.date = date
        self.waitTime = waitTime
    }

    // Exclude id from the encoded payload — it's ephemeral and regenerated on decode.
    enum CodingKeys: String, CodingKey { case date, waitTime }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        date = try c.decode(Date.self, forKey: .date)
        waitTime = try c.decode(Int.self, forKey: .waitTime)
    }
}
