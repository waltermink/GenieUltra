import Foundation

struct DestinationsResponse: Codable {
    let destinations: [DestinationEntry]
}

struct DestinationEntry: Codable {
    let id: String
    let name: String
    let slug: String
    let parks: [ParkEntry]
}

struct ParkEntry: Codable, Identifiable {
    let id: String
    let name: String
}

// MARK: - Entity Children

struct EntityChildrenResponse: Codable {
    let children: [EntityChild]
}

struct EntityChild: Codable, Identifiable {
    let id: String
    let name: String
    let entityType: String
}
