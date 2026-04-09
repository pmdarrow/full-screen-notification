import Foundation

struct CalendarEvent: Codable, Identifiable, Hashable {
    let id: String
    let summary: String?
    let start: EventDateTime
    let end: EventDateTime
    let hangoutLink: String?
    let conferenceData: ConferenceData?
    let htmlLink: String?
    let status: String?

    var title: String {
        summary ?? "(No title)"
    }

    var videoCallURL: URL? {
        if let hangoutLink, let url = URL(string: hangoutLink) {
            return url
        }
        if let entryPoint = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" }),
           let uri = entryPoint.uri,
           let url = URL(string: uri) {
            return url
        }
        return nil
    }

    var startDate: Date? {
        start.dateTime ?? start.allDayDate
    }

    var endDate: Date? {
        end.dateTime ?? end.allDayDate
    }

    var isAllDay: Bool {
        start.date != nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct EventDateTime: Codable {
    let dateTime: Date?
    let date: String?
    let timeZone: String?

    var allDayDate: Date? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}

struct ConferenceData: Codable {
    let entryPoints: [EntryPoint]?
    let conferenceSolution: ConferenceSolution?
}

struct EntryPoint: Codable {
    let entryPointType: String?
    let uri: String?
    let label: String?
}

struct ConferenceSolution: Codable {
    let name: String?
    let iconUri: String?
}

struct EventsListResponse: Codable {
    let items: [CalendarEvent]?
}
