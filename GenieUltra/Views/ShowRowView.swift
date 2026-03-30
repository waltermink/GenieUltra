import SwiftUI

struct ShowRowView: View {
    let show: EntityLiveData

    private var showtimeList: [ShowTime] {
        show.showtimes ?? []
    }

    private var nextShowtime: ShowTime? {
        let now = Date()
        return showtimeList.first { showtime in
            guard let startStr = showtime.startTime,
                  let startDate = TimeFormatter.parseISO(startStr) else {
                return false
            }
            return startDate > now
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(show.name)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                if show.status == "OPERATING" {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
            }

            if showtimeList.isEmpty {
                Text("No showtimes available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                showtimePills
            }
        }
        .padding(.vertical, 4)
    }

    private var showtimePills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(showtimeList) { showtime in
                    showtimePill(for: showtime)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func showtimePill(for showtime: ShowTime) -> some View {
        if let startStr = showtime.startTime {
            let isPast = isPastShowtime(startStr)
            let isNext = isNextShowtime(showtime)

            Text(TimeFormatter.formatTime(startStr))
                .font(.caption)
                .fontWeight(isNext ? .bold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isNext ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                .foregroundColor(isPast ? .gray : (isNext ? .blue : .primary))
                .clipShape(Capsule())
        }
    }

    private func isPastShowtime(_ isoString: String) -> Bool {
        guard let date = TimeFormatter.parseISO(isoString) else { return false }
        return date < Date()
    }

    private func isNextShowtime(_ showtime: ShowTime) -> Bool {
        guard let next = nextShowtime else { return false }
        return showtime.startTime == next.startTime
    }
}
