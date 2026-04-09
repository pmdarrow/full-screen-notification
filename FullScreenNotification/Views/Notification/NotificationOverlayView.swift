import SwiftUI

struct NotificationOverlayView: View {
    let event: CalendarEvent
    let onJoin: (URL) -> Void
    let onDismiss: () -> Void

    @State private var currentDate = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                // Clock in top-right
                HStack {
                    Spacer()
                    Text(DateFormatting.formatTime(currentDate))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                }

                Spacer()

                // Event info centered
                EventInfoView(
                    event: event,
                    currentDate: currentDate
                )

                Spacer()
                    .frame(height: 40)

                // Action buttons
                ActionButtonsView(
                    event: event,
                    onJoin: onJoin,
                    onDismiss: onDismiss
                )

                Spacer()
            }
        }
        .onReceive(timer) { date in
            currentDate = date
        }
    }
}
