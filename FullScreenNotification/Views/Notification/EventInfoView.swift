import SwiftUI

struct EventInfoView: View {
    let event: CalendarEvent
    let currentDate: Date

    var body: some View {
        VStack(spacing: 12) {
            // Event title
            Text(event.title)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Time range
            if let start = event.startDate, let end = event.endDate {
                Text(DateFormatting.formatTimeRange(start: start, end: end))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }

            // Relative time
            if let start = event.startDate {
                Text(DateFormatting.formatRelativeTime(from: currentDate, to: start))
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 4)
            }

        }
    }
}

