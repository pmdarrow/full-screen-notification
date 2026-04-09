import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusSection

            Divider()

            upcomingSection

            Divider()

            alertSection

            Divider()

            actionSection

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
    }

    private var alertSection: some View {
        Picker("Alert Before", selection: $appState.minutesBefore) {
            Text("1 minute").tag(1)
            Text("2 minutes").tag(2)
            Text("3 minutes").tag(3)
            Text("5 minutes").tag(5)
            Text("10 minutes").tag(10)
            Text("15 minutes").tag(15)
        }
        .onChange(of: appState.minutesBefore) {
            appState.refreshMonitoring()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.isAuthenticated ? "Google Calendar connected" : "Google Calendar not connected")
                .font(.headline)

            if let email = appState.oauthService.currentUserEmail, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let authIssue = appState.authIssue {
                Text(authIssue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if appState.isAuthenticated {
            if appState.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upcoming")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("No upcoming events")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upcoming")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(appState.upcomingEvents.prefix(3)) { event in
                        eventRow(event)
                    }
                }
            }
        } else {
            Text("Connect to Google Calendar to see upcoming events.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionSection: some View {
        Group {
            if appState.isAuthenticated {
                Button("Disconnect from Google Calendar") {
                    appState.signOut()
                }
            } else {
                Button("Connect to Google Calendar") {
                    appState.signIn()
                }
            }

            Button("Show Sample Notification") {
                appState.showSampleNotification()
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .lineLimit(1)

            Text(relativeTime(for: event))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func relativeTime(for event: CalendarEvent) -> String {
        guard let start = event.startDate else { return "" }
        return DateFormatting.formatRelativeTime(from: Date(), to: start)
    }
}
