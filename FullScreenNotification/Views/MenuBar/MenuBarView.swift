import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            statusSection

            if appState.isAuthenticated {
                Divider()

                upcomingSection

                Divider()

                alertSection
            }

            Divider()

            actionSection
        }
    }

    private var alertSection: some View {
        Picker("Alert before", selection: $appState.minutesBefore) {
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
        Group {
            Label(
                appState.isAuthenticated ? "Google Calendar connected" : "Google Calendar not connected",
                systemImage: appState.isAuthenticated ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .labelStyle(.titleAndIcon)

            if let email = appState.oauthService.currentUserEmail, !email.isEmpty {
                Text(email)
            }

            if let authIssue = appState.authIssue {
                Text(authIssue.message)
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        Text("Next Alert")
            .foregroundStyle(.secondary)

        if appState.upcomingEvents.isEmpty {
            Text("No upcoming timed meetings.")
        } else if let event = appState.upcomingEvents.first {
            eventRow(event)
        }
    }

    private var actionSection: some View {
        Group {
            if appState.isAuthenticated {
                Button("Show Sample Notification") {
                    appState.showSampleNotification()
                }

                Button("Disconnect Calendar...") {
                    appState.signOut()
                }

                Divider()
            } else {
                Button("Connect Google Calendar") {
                    appState.signIn()
                }

                Divider()
            }

            Button("Quit Full Screen Notification") {
                NSApp.terminate(nil)
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        Group {
            Text(event.title)

            Text("\(eventTimeText(for: event)) | \(relativeTime(for: event))")
                .foregroundStyle(.secondary)
        }
    }

    private func relativeTime(for event: CalendarEvent) -> String {
        guard let start = event.startDate else { return "" }
        return DateFormatting.formatCompactRelativeTime(from: Date(), to: start)
    }

    private func eventTimeText(for event: CalendarEvent) -> String {
        guard let start = event.startDate else { return "Timed event" }
        let startsToday = Calendar.current.isDateInToday(start)

        if let end = event.endDate {
            if startsToday {
                return DateFormatting.formatTimeRange(start: start, end: end)
            }

            return DateFormatting.formatEventDateTime(start)
        }

        if startsToday {
            return DateFormatting.formatEventTime(start)
        }

        return DateFormatting.formatEventDateTime(start)
    }
}
