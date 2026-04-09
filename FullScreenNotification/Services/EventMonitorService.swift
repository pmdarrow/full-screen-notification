import Foundation

@MainActor
final class EventMonitorService {
    var onEventTriggered: ((CalendarEvent) -> Void)?

    private var timer: Timer?
    private var notifiedEventIDs: Set<String> = []
    private var calendarService: GoogleCalendarService?
    private var minutesBefore: Int = 5
    private var onEventsUpdated: (([CalendarEvent]) -> Void)?

    func start(
        calendarService: GoogleCalendarService,
        minutesBefore: Int,
        onEventsUpdated: @escaping ([CalendarEvent]) -> Void
    ) {
        self.calendarService = calendarService
        self.minutesBefore = minutesBefore
        self.onEventsUpdated = onEventsUpdated

        // Fetch immediately on start
        Task { await fetchAndProcess() }

        // Then poll every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAndProcess()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func fetchAndProcess() async {
        guard let calendarService else { return }

        do {
            let events = try await calendarService.fetchUpcomingEvents(
                withinMinutes: minutesBefore
            )

            onEventsUpdated?(events)

            // Trigger notification for events not yet notified
            for event in events {
                guard !notifiedEventIDs.contains(event.id) else { continue }
                guard !event.isAllDay else { continue }

                notifiedEventIDs.insert(event.id)
                onEventTriggered?(event)
            }

            // Clean up old notified IDs (events that are now in the past)
            let now = Date()
            notifiedEventIDs = notifiedEventIDs.filter { id in
                events.contains { $0.id == id && ($0.endDate ?? .distantPast) > now }
            }
        } catch {
            print("Event monitor fetch failed: \(error)")
        }
    }
}
