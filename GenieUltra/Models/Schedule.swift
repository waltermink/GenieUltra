import Foundation

struct EntityScheduleResponse: Codable {
    let schedule: [ScheduleEntry]
}

struct ScheduleEntry: Codable, Identifiable {
    let date: String?
    let type: String?
    let openingTime: String?
    let closingTime: String?

    var id: String { "\(date ?? "")-\(type ?? "")" }
}
