import SwiftUI

struct ParkHeaderView: View {
    let schedule: ScheduleEntry?
    let lastRefreshed: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Park hours
            if let schedule,
               let opening = schedule.openingTime,
               let closing = schedule.closingTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("\(TimeFormatter.formatTime(opening)) – \(TimeFormatter.formatTime(closing))")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            // Last updated
            if let lastRefreshed {
                let seconds = Int(Date().timeIntervalSince(lastRefreshed))
                let text = seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                    Text("Updated \(text)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
