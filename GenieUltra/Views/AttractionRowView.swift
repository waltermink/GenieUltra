import SwiftUI

struct AttractionRowView: View {
    let attraction: EntityLiveData

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Name and LL info
            VStack(alignment: .leading, spacing: 4) {
                Text(attraction.name)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let returnTime = attraction.queue?.returnTime {
                        llBadge(label: "LL", returnTime: returnTime)
                    }
                    if let paidReturn = attraction.queue?.paidReturnTime {
                        llBadge(label: "SP", returnTime: paidReturn)
                    }
                }
            }

            Spacer()

            // Wait time
            waitTimeView
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status

    private var statusColor: Color {
        switch attraction.status {
        case "OPERATING": return .green
        case "DOWN": return .red
        case "CLOSED": return .gray
        case "REFURBISHMENT": return .orange
        default: return .gray
        }
    }

    // MARK: - Wait Time

    @ViewBuilder
    private var waitTimeView: some View {
        if attraction.status == "OPERATING" {
            if let waitTime = attraction.queue?.standby?.waitTime {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(waitTime)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(WaitTimeColor.color(for: waitTime))
                    Text("min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 50, alignment: .trailing)
            } else {
                Text("--")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.gray)
                    .frame(minWidth: 50, alignment: .trailing)
            }
        } else {
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 50, alignment: .trailing)
        }
    }

    private var statusLabel: String {
        switch attraction.status {
        case "CLOSED": return "Closed"
        case "DOWN": return "Down"
        case "REFURBISHMENT": return "Rehab"
        default: return attraction.status ?? "Unknown"
        }
    }

    // MARK: - Lightning Lane Badge

    @ViewBuilder
    private func llBadge(label: String, returnTime: ReturnTimeQueue) -> some View {
        if returnTime.state == "AVAILABLE", let start = returnTime.returnStart {
            Text("\(label): \(TimeFormatter.formatTime(start))")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        } else if returnTime.state == "FINISHED" {
            Text("\(label): Sold Out")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.gray.opacity(0.1))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }
}
// MARK: - Preview

#Preview {
    List {
        Section("Operating — With Wait & LL") {
            AttractionRowView(attraction: EntityLiveData(
                id: "1",
                name: "Space Mountain",
                entityType: "ATTRACTION",
                status: "OPERATING",
                lastUpdated: nil,
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 45),
                    returnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T14:30:00", returnEnd: nil),
                    paidReturnTime: nil
                ),
                showtimes: nil,
                forecast: nil
            ))

            AttractionRowView(attraction: EntityLiveData(
                id: "2",
                name: "TRON Lightcycle / Run",
                entityType: "ATTRACTION",
                status: "OPERATING",
                lastUpdated: nil,
                queue: QueueData(
                    standby: StandbyQueue(waitTime: 90),
                    returnTime: ReturnTimeQueue(state: "FINISHED", returnStart: nil, returnEnd: nil),
                    paidReturnTime: ReturnTimeQueue(state: "AVAILABLE", returnStart: "2026-03-30T16:00:00", returnEnd: nil)
                ),
                showtimes: nil,
                forecast: nil
            ))
        }

        Section("Operating — No Wait Time") {
            AttractionRowView(attraction: EntityLiveData(
                id: "3",
                name: "Walt Disney's Carousel of Progress",
                entityType: "ATTRACTION",
                status: "OPERATING",
                lastUpdated: nil,
                queue: QueueData(
                    standby: StandbyQueue(waitTime: nil),
                    returnTime: nil,
                    paidReturnTime: nil
                ),
                showtimes: nil,
                forecast: nil
            ))
        }

        Section("Non-Operating States") {
            AttractionRowView(attraction: EntityLiveData(
                id: "4",
                name: "Splash Mountain",
                entityType: "ATTRACTION",
                status: "CLOSED",
                lastUpdated: nil,
                queue: nil,
                showtimes: nil,
                forecast: nil
            ))

            AttractionRowView(attraction: EntityLiveData(
                id: "5",
                name: "Seven Dwarfs Mine Train",
                entityType: "ATTRACTION",
                status: "DOWN",
                lastUpdated: nil,
                queue: nil,
                showtimes: nil,
                forecast: nil
            ))

            AttractionRowView(attraction: EntityLiveData(
                id: "6",
                name: "Pirates of the Caribbean",
                entityType: "ATTRACTION",
                status: "REFURBISHMENT",
                lastUpdated: nil,
                queue: nil,
                showtimes: nil,
                forecast: nil
            ))
        }
    }
}

