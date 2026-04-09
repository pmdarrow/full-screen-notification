import SwiftUI

struct ActionButtonsView: View {
    let event: CalendarEvent
    let onJoin: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let url = event.videoCallURL {
                Button {
                    onJoin(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 16))
                        Text("Join")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(width: 280, height: 48)
                    .contentShape(Rectangle())
                    .background(Color.accentYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            Button {
                onDismiss()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 280, height: 48)
                    .contentShape(Rectangle())
                    .background(.white.opacity(0.001))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

extension Color {
    static let accentYellow = Color(red: 0.91, green: 0.72, blue: 0.22)
}
