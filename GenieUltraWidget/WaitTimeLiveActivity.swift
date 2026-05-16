import ActivityKit
import SwiftUI
import WidgetKit

// NOTE: WaitTimeActivityAttributes and AttractionSnapshot are defined in
// GenieUltra/LiveActivity/WaitTimeActivityAttributes.swift. That file must be
// added to this (widget extension) target's membership in Xcode:
//   Select the file → File Inspector (⌥⌘1) → check GenieUltraWidgetExtension.

// MARK: - Lock Screen / Expanded View

struct WaitTimeLockScreenView: View {
    let context: ActivityViewContext<WaitTimeActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label(context.attributes.parkName, systemImage: "flag.fill")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Text(context.state.lastUpdated, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Attraction rows — up to 4 in expanded, fewer in compact
            ForEach(context.state.snapshots.prefix(4)) { snapshot in
                LiveActivityAttractionRow(snapshot: snapshot)
            }
        }
        .padding(14)
    }
}

// MARK: - Attraction Row

private struct LiveActivityAttractionRow: View {
    let snapshot: AttractionSnapshot

    private var statusColor: Color {
        switch snapshot.status {
        case "OPERATING": return .green
        case "DOWN":      return .red
        default:          return .gray
        }
    }

    private var waitText: String {
        guard snapshot.isOperating else {
            return snapshot.status == "DOWN" ? "Down" : "Closed"
        }
        if let wait = snapshot.waitMinutes { return "\(wait)m" }
        return "—"
    }

    private var waitColor: Color {
        guard snapshot.isOperating, let wait = snapshot.waitMinutes else { return .secondary }
        switch wait {
        case ..<20:  return .green
        case ..<45:  return .yellow
        case ..<75:  return .orange
        default:     return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(snapshot.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if snapshot.llAvailable, let rt = snapshot.llReturnStart {
                llBadge("⚡", time: rt)
            } else if snapshot.paAvailable, let rt = snapshot.paReturnStart {
                llBadge("⚡+", time: rt)
            }

            Text(waitText)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(waitColor)
                .frame(minWidth: 28, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func llBadge(_ prefix: String, time: String) -> some View {
        Text("\(prefix) \(formattedTime(time))")
            .font(.caption2)
            .foregroundStyle(.blue)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.12))
            .clipShape(Capsule())
    }

    private func formattedTime(_ isoString: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: isoString) else { return isoString }
        let df = DateFormatter()
        df.dateFormat = "h:mm"
        return df.string(from: date)
    }
}

// MARK: - Dynamic Island Views

private struct DynamicIslandCompactLeading: View {
    let context: ActivityViewContext<WaitTimeActivityAttributes>

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.caption2)
            .foregroundStyle(.yellow)
    }
}

private struct DynamicIslandCompactTrailing: View {
    let context: ActivityViewContext<WaitTimeActivityAttributes>

    // Show the most urgent info: first LL-available attraction, else shortest wait.
    private var summary: String {
        if let llSnap = context.state.snapshots.first(where: { $0.llAvailable || $0.paAvailable }),
           let rt = llSnap.llReturnStart ?? llSnap.paReturnStart {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: rt) {
                let df = DateFormatter(); df.dateFormat = "h:mm"
                return "LL \(df.string(from: date))"
            }
        }
        if let wait = context.state.snapshots.compactMap(\.waitMinutes).min() {
            return "\(wait)m"
        }
        return "—"
    }

    var body: some View {
        Text(summary)
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}

private struct DynamicIslandExpanded: View {
    let context: ActivityViewContext<WaitTimeActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(context.attributes.parkName)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Text(context.state.lastUpdated, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(context.state.snapshots.prefix(3)) { snapshot in
                LiveActivityAttractionRow(snapshot: snapshot)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Widget Registration

struct WaitTimeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WaitTimeActivityAttributes.self) { context in
            WaitTimeLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.parkName, systemImage: "flag.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.lastUpdated, style: .time)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandExpanded(context: context)
                }
            } compactLeading: {
                DynamicIslandCompactLeading(context: context)
            } compactTrailing: {
                DynamicIslandCompactTrailing(context: context)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}
