import Foundation

enum ThemeParksAPI {
    private static let baseURL = "https://api.themeparks.wiki/v1"

    static func fetchDestinations() async throws -> DestinationsResponse {
        let data = try await fetchData(from: "\(baseURL)/destinations")
        return try JSONDecoder().decode(DestinationsResponse.self, from: data)
    }

    static func fetchEntityChildren(entityID: String) async throws -> EntityChildrenResponse {
        let data = try await fetchData(from: "\(baseURL)/entity/\(entityID)/children")
        return try JSONDecoder().decode(EntityChildrenResponse.self, from: data)
    }

    static func fetchEntityLiveData(entityID: String) async throws -> EntityLiveDataResponse {
        let data = try await fetchData(from: "\(baseURL)/entity/\(entityID)/live")
        return try JSONDecoder().decode(EntityLiveDataResponse.self, from: data)
    }

    static func fetchEntitySchedule(entityID: String) async throws -> EntityScheduleResponse {
        let data = try await fetchData(from: "\(baseURL)/entity/\(entityID)/schedule")
        return try JSONDecoder().decode(EntityScheduleResponse.self, from: data)
    }

    private static func fetchData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
        return data
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server error (HTTP \(code))"
        }
    }
}
