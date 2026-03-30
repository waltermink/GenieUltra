import SwiftUI
import Charts

struct AttractionDetailView: View {
    let attraction: EntityLiveData
    let history: [WaitTimeRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let lastUpdated = attraction.lastUpdated {
                        Text("Updated \(TimeFormatter.formatTime(lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Standby wait time
                if let waitTime = attraction.queue?.standby?.waitTime {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Standby Wait")
                            .font(.headline)
                        Text("\(waitTime) minutes")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(WaitTimeColor.color(for: waitTime))
                    }
                }

                // Lightning Lane Multi Pass
                if let returnTime = attraction.queue?.returnTime {
                    queueSection(title: "Lightning Lane Multi Pass", returnTime: returnTime)
                }

                // Lightning Lane Single Pass
                if let paidReturn = attraction.queue?.paidReturnTime {
                    queueSection(title: "Lightning Lane Single Pass", returnTime: paidReturn)
                }

                // Wait time history chart
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wait Time History")
                            .font(.headline)

                        Chart(history) { entry in
                            LineMark(
                                x: .value("Time", entry.date),
                                y: .value("Wait", entry.waitTime)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Time", entry.date),
                                y: .value("Wait", entry.waitTime)
                            )
                            .foregroundStyle(.blue.opacity(0.1))
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYAxisLabel("Minutes")
                        .frame(height: 200)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(attraction.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch attraction.status {
        case "OPERATING": return .green
        case "DOWN": return .red
        case "CLOSED": return .gray
        case "REFURBISHMENT": return .orange
        default: return .gray
        }
    }

    private var statusText: String {
        switch attraction.status {
        case "OPERATING": return "Operating"
        case "DOWN": return "Temporarily Down"
        case "CLOSED": return "Closed"
        case "REFURBISHMENT": return "Under Refurbishment"
        default: return attraction.status ?? "Unknown"
        }
    }

    @ViewBuilder
    private func queueSection(title: String, returnTime: ReturnTimeQueue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            if returnTime.state == "AVAILABLE" {
                if let start = returnTime.returnStart, let end = returnTime.returnEnd {
                    Text("Return: \(TimeFormatter.formatTime(start)) – \(TimeFormatter.formatTime(end))")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
            } else {
                Text("Sold Out")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
// MARK: - Preview

private extension AttractionDetailView {
    /// Generates sample wait-time records for the chart preview.
    static func sampleHistory() -> [WaitTimeRecord] {
        let calendar = Calendar.current
        let now = Date()
        let waits = [25, 30, 40, 55, 65, 70, 60, 50, 45, 35, 40, 55, 70, 80, 75, 60]
        return waits.enumerated().map { index, wait in
            WaitTimeRecord(
                date: calendar.date(byAdding: .minute, value: -((waits.count - 1 - index) * 15), to: now)!,
                waitTime: wait
            )
        }
    }
}

#Preview("Operating — Full") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "1",
                name: "Space Mountain",
                entityType: "ATTRACTION",
                status: "OPERATING",
                lastUpdated: "2026-03-30T14:22:00Z",
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 65),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T15:00:00", returnEnd: "2026-03-30T15:30:00"),
                    paidReturnTime: nil
                ),
                showtimes: nil
            ),
            history: AttractionDetailView.sampleHistory()
        )
    }
}

#Preview("Operating — LL Sold Out + ILL") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "2",
                name: "TRON Lightcycle / Run",
                entityType: "ATTRACTION",
                status: "OPERATING",
                lastUpdated: "2026-03-30T14:10:00Z",
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 90),
                    returnTime: ReturnTimeQueue(state: "FINISHED", returnStart: nil, returnEnd: nil),
                    paidReturnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T16:00:00", returnEnd: "2026-03-30T16:30:00")
                ),
                showtimes: nil
            ),
            history: AttractionDetailView.sampleHistory()
        )
    }
}

#Preview("Closed") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "3",
                name: "Splash Mountain",
                entityType: "ATTRACTION",
                status: "CLOSED",
                lastUpdated: nil,
                queue: nil,
                showtimes: nil
            ),
            history: []
        )
    }
}

#Preview("Down") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "4",
                name: "Seven Dwarfs Mine Train",
                entityType: "ATTRACTION",
                status: "DOWN",
                lastUpdated: "2026-03-30T13:45:00Z",
                queue: nil,
                showtimes: nil
            ),
            history: AttractionDetailView.sampleHistory()
        )
    }
}

