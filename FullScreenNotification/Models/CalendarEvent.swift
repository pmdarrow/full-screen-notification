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
    let description: String?
    let location: String?

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
        if let url = VideoCallLinkDetector.firstMeetingURL(in: [location, description]) {
            return url
        }
        return nil
    }

    var startDate: Date? {
        start.dateTime
    }

    var endDate: Date? {
        end.dateTime
    }

    var isAllDay: Bool {
        start.date != nil && start.dateTime == nil
    }

    var canTriggerAlert: Bool {
        status != "cancelled" && startDate != nil && !isAllDay
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

private enum VideoCallLinkDetector {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static let meetingHosts = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "teamsonline.microsoft.com",
        "teams.live.com",
        "webex.com",
        "meet.jit.si",
        "whereby.com",
        "bluejeans.com",
        "gotomeet.me",
        "gotomeeting.com",
    ]

    static func firstMeetingURL(in texts: [String?]) -> URL? {
        guard let detector else { return nil }

        for text in texts.compactMap({ $0?.normalizedCalendarText }).filter({ !$0.isEmpty }) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                guard let url = match.url,
                      let meetingURL = meetingURL(from: url) else {
                    continue
                }

                return meetingURL
            }
        }

        return nil
    }

    private static func meetingURL(from url: URL) -> URL? {
        if isMeetingURL(url) {
            return url
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        for itemName in ["q", "url"] {
            guard let value = queryItems.first(where: { $0.name == itemName })?.value,
                  let nestedURL = URL(string: value),
                  isMeetingURL(nestedURL) else {
                continue
            }

            return nestedURL
        }

        return nil
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return meetingHosts.contains { meetingHost in
            host == meetingHost || host.hasSuffix(".\(meetingHost)")
        }
    }
}

private extension String {
    var normalizedCalendarText: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
