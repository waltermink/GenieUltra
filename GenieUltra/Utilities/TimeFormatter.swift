import Foundation

enum TimeFormatter {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static func parseISO(_ string: String) -> Date? {
        isoWithFractional.date(from: string) ?? isoBasic.date(from: string)
    }

    static func formatTime(_ isoString: String) -> String {
        guard let date = parseISO(isoString) else { return isoString }
        return timeOnly.string(from: date)
    }

    static func formatTime(_ date: Date) -> String {
        timeOnly.string(from: date)
    }
}
