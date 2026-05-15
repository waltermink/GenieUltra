import SwiftUI
import Charts

struct AttractionDetailView: View {
    let attraction: EntityLiveData
    let history: [WaitTimeRecord]

    // Parsed forecast entries — filters out any entries whose time string can't be decoded.
    private struct ForecastPoint: Identifiable {
        let id = UUID()
        let date: Date
        let waitTime: Int
    }

    private var forecastPoints: [ForecastPoint] {
        (attraction.forecast ?? []).compactMap { entry in
            guard let date = TimeFormatter.parseISO(entry.time) else { return nil }
            return ForecastPoint(date: date, waitTime: entry.waitTime)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Status row
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

                // Current standby wait
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

                // Predicted wait time chart (forecast from API)
                if !forecastPoints.isEmpty {
                    forecastChart
                }

                // Live wait time history chart (recorded during this session)
                if !history.isEmpty {
                    historyChart
                }
            }
            .padding()
        }
        .navigationTitle(attraction.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Forecast Chart

    private var forecastChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Predicted Wait Times")
                .font(.headline)

            let yMax = max((forecastPoints.map(\.waitTime).max() ?? 60) + 10, 60)

            Chart {
                ForEach(forecastPoints) { point in
                    BarMark(
                        x: .value("Time", point.date, unit: .hour),
                        y: .value("Wait", point.waitTime)
                    )
                    .foregroundStyle(
                        point.date < Date()
                            ? Color.secondary.opacity(0.35)
                            : WaitTimeColor.color(for: point.waitTime).opacity(0.85)
                    )
                }

                // Current time marker
                RuleMark(x: .value("Now", Date()))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Now")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartYAxisLabel("min")
            .frame(height: 200)
        }
    }

    // MARK: - History Chart

    private var historyChart: some View {
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

// MARK: - Preview Helpers

private extension AttractionDetailView {
    static func sampleHistory() -> [WaitTimeRecord] {
        let now = Date()
        let waits = [25, 30, 40, 55, 65, 70, 60, 50, 45, 35, 40, 55, 70, 80, 75, 60]
        return waits.enumerated().map { index, wait in
            WaitTimeRecord(
                date: Calendar.current.date(byAdding: .minute, value: -((waits.count - 1 - index) * 15), to: now)!,
                waitTime: wait
            )
        }
    }

    static func sampleForecast() -> [ForecastEntry] {
        let waits = [40, 50, 65, 70, 80, 85, 90, 95, 100, 85, 75, 60, 45, 30]
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startOfDay = calendar.startOfDay(for: Date())
        return waits.enumerated().map { index, wait in
            let date = calendar.date(byAdding: .hour, value: 9 + index, to: startOfDay)!
            return ForecastEntry(time: formatter.string(from: date), waitTime: wait, percentage: wait)
        }
    }
}

#Preview("Operating — Forecast + History") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "1", name: "Space Mountain", entityType: "ATTRACTION",
                status: "OPERATING", lastUpdated: "2026-05-15T14:22:00Z",
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 65),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-05-15T15:00:00", returnEnd: "2026-05-15T15:30:00"),
                    paidReturnTime: nil
                ),
                showtimes: nil,
                forecast: AttractionDetailView.sampleForecast()
            ),
            history: AttractionDetailView.sampleHistory()
        )
    }
}

#Preview("Operating — No Forecast") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "2", name: "Haunted Mansion", entityType: "ATTRACTION",
                status: "OPERATING", lastUpdated: "2026-05-15T14:10:00Z",
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 30),
                    returnTime: nil, paidReturnTime: nil
                ),
                showtimes: nil,
                forecast: nil
            ),
            history: AttractionDetailView.sampleHistory()
        )
    }
}

#Preview("Meet & Greet") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "mg1", name: "Mickey Mouse", entityType: "SHOW",
                status: "OPERATING", lastUpdated: "2026-05-15T13:00:00Z",
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 20),
                    returnTime: nil, paidReturnTime: nil
                ),
                showtimes: nil,
                forecast: AttractionDetailView.sampleForecast()
            ),
            history: []
        )
    }
}

#Preview("Down") {
    NavigationStack {
        AttractionDetailView(
            attraction: EntityLiveData(
                id: "3", name: "Seven Dwarfs Mine Train", entityType: "ATTRACTION",
                status: "DOWN", lastUpdated: "2026-05-15T13:45:00Z",
                queue: nil, showtimes: nil, forecast: nil
            ),
            history: AttractionDetailView.sampleHistory()
        )
    }
}
