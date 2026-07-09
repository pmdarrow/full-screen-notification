import Foundation

@MainActor
final class EventMonitorService {
    var onEventTriggered: ((CalendarEvent) -> Void)?

    private var timer: Timer?
    private var scheduledAlerts: [String: ScheduledAlert] = [:]
    private var notifiedEventIDs: Set<String> = []
    private var calendarService: GoogleCalendarService?
    private var minutesBefore: Int = 5
    private var onEventsUpdated: (([CalendarEvent]) -> Void)?

    func start(
        calendarService: GoogleCalendarService,
        minutesBefore: Int,
        onEventsUpdated: @escaping ([CalendarEvent]) -> Void
    ) {
        stop()

        self.calendarService = calendarService
        self.minutesBefore = minutesBefore
        self.onEventsUpdated = onEventsUpdated

        // Fetch immediately on start
        Task { await fetchAndProcess() }

        // Then poll for calendar changes while exact alert timers handle notification timing.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAndProcess()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scheduledAlerts.values.forEach { $0.timer.invalidate() }
        scheduledAlerts = [:]
    }

    private func fetchAndProcess() async {
        guard let calendarService else { return }

        do {
            let events = try await calendarService.fetchUpcomingEvents()

            onEventsUpdated?(events)

            let now = Date()
            scheduleAlerts(for: events, now: now)

            // Clean up old notified IDs (events that are now in the past)
            notifiedEventIDs = notifiedEventIDs.filter { id in
                events.contains { $0.id == id && ($0.endDate ?? .distantPast) > now }
            }
        } catch {
            print("Event monitor fetch failed: \(error)")
        }
    }

    private func scheduleAlerts(for events: [CalendarEvent], now: Date) {
        let activeEventIDs = Set(events.map(\.id))
        let inactiveAlertIDs = scheduledAlerts.keys.filter { id in
            !activeEventIDs.contains(id) || notifiedEventIDs.contains(id)
        }

        for id in inactiveAlertIDs {
            scheduledAlerts[id]?.timer.invalidate()
            scheduledAlerts[id] = nil
        }

        for event in events {
            guard !notifiedEventIDs.contains(event.id) else { continue }
            guard event.canTriggerAlert, let startDate = event.startDate, startDate > now else { continue }

            let alertDate = startDate.addingTimeInterval(-TimeInterval(minutesBefore * 60))
            if alertDate <= now {
                triggerAlert(for: event)
                continue
            }

            if let scheduledAlert = scheduledAlerts[event.id] {
                if abs(scheduledAlert.alertDate.timeIntervalSince(alertDate)) < 0.5 {
                    continue
                }

                scheduledAlert.timer.invalidate()
                scheduledAlerts[event.id] = nil
            }

            let timer = Timer(timeInterval: alertDate.timeIntervalSince(now), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.triggerAlert(for: event)
                }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            scheduledAlerts[event.id] = ScheduledAlert(alertDate: alertDate, timer: timer)
        }
    }

    private func triggerAlert(for event: CalendarEvent) {
        guard !notifiedEventIDs.contains(event.id) else { return }
        guard event.canTriggerAlert, let startDate = event.startDate, startDate > Date() else { return }

        scheduledAlerts[event.id]?.timer.invalidate()
        scheduledAlerts[event.id] = nil
        notifiedEventIDs.insert(event.id)
        onEventTriggered?(event)
    }
}

private struct ScheduledAlert {
    let alertDate: Date
    let timer: Timer
}
