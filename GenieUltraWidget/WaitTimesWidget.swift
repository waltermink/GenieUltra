import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct WaitTimesProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaitTimesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WaitTimesEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaitTimesEntry>) -> Void) {
        let entry = makeEntry()
        // Suggest a refresh in 15 minutes; iOS may honour it later.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> WaitTimesEntry {
        let defaults = UserDefaults(suiteName: WidgetSharedKeys.appGroupID) ?? .standard
        let selectedIDs = defaults.stringArray(forKey: WidgetSharedKeys.widgetAttractionIDs) ?? []
        let lastUpdated = defaults.object(forKey: WidgetSharedKeys.timestampKey) as? Date

        var attractions: [WidgetEntity] = []
        if let data = defaults.data(forKey: WidgetSharedKeys.liveDataKey),
           let response = try? JSONDecoder().decode(WidgetLiveDataResponse.self, from: data) {
            if selectedIDs.isEmpty {
                // Nothing configured yet — show the first few operating attractions
                attractions = response.liveData
                    .filter { $0.status == "OPERATING" }
                    .prefix(4)
                    .map { $0 }
            } else {
                // Show in the order the user selected
                attractions = selectedIDs.compactMap { id in
                    response.liveData.first { $0.id == id }
                }
            }
        }

        return WaitTimesEntry(date: Date(), attractions: attractions, lastUpdated: lastUpdated)
    }
}

// MARK: - Widget Definition

struct WaitTimesWidget: Widget {
    let kind = "WaitTimesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaitTimesProvider()) { entry in
            WaitTimesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Wait Times")
        .description("Shows current wait times for your selected attractions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct WaitTimesWidgetView: View {
    let entry: WaitTimesEntry
    @Environment(\.widgetFamily) private var family

    private var maxRows: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Magic Kingdom")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                if let updated = entry.lastUpdated {
                    Text(updated, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(intent: RefreshWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            if entry.attractions.isEmpty {
                Spacer()
                Text("No attractions selected.\nOpen GenieUltra → Settings → Widget Attractions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(entry.attractions.prefix(maxRows).enumerated()), id: \.element.id) { idx, attraction in
                    if idx > 0 { Divider().padding(.vertical, 3) }
                    AttractionWidgetRow(attraction: attraction)
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }
}

// MARK: - Attraction Row

private struct AttractionWidgetRow: View {
    let attraction: WidgetEntity

    private var statusColor: Color {
        switch attraction.status {
        case "OPERATING": return .green
        case "DOWN":      return .red
        default:          return .gray
        }
    }

    private var waitText: String {
        guard attraction.status == "OPERATING" else {
            return attraction.status == "DOWN" ? "Down" : "Closed"
        }
        if let wait = attraction.queue?.standby?.waitTime { return "\(wait) min" }
        return "—"
    }

    private var llText: String? {
        if let rt = attraction.queue?.returnTime, rt.state == "AVAILABLE", let start = rt.returnStart {
            return "LL \(formatTime(start))"
        }
        if let pa = attraction.queue?.paidReturnTime, pa.state == "AVAILABLE", let start = pa.returnStart {
            return "PA \(formatTime(start))"
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(attraction.name)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            if let ll = llText {
                Text(ll)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            Text(waitText)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(waitColor)
                .frame(minWidth: 36, alignment: .trailing)
        }
    }

    private var waitColor: Color {
        guard attraction.status == "OPERATING",
              let wait = attraction.queue?.standby?.waitTime else { return .secondary }
        switch wait {
        case ..<20:  return .green
        case ..<45:  return .yellow
        case ..<75:  return .orange
        default:     return .red
        }
    }

    private func formatTime(_ isoString: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: isoString) else { return isoString }
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: date)
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    WaitTimesWidget()
} timeline: {
    WaitTimesEntry.placeholder
}

#Preview(as: .systemLarge) {
    WaitTimesWidget()
} timeline: {
    WaitTimesEntry.placeholder
}
