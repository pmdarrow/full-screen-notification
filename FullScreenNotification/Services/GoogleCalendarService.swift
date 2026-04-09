import Foundation

final class GoogleCalendarService: @unchecked Sendable {
    private let oauthService: GoogleOAuthService
    private let session = URLSession.shared
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    init(oauthService: GoogleOAuthService) {
        self.oauthService = oauthService
    }

    func fetchUpcomingEvents(withinMinutes minutes: Int) async throws -> [CalendarEvent] {
        try await oauthService.refreshTokenIfNeeded()

        guard let accessToken = await oauthService.accessToken else {
            throw OAuthError.notAuthenticated
        }

        let now = Date()
        let future = now.addingTimeInterval(TimeInterval(minutes * 60))

        return try await fetchEvents(
            calendarID: "primary",
            accessToken: accessToken,
            timeMin: now,
            timeMax: future
        )
        .filter { $0.status != "cancelled" }
        .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private func fetchEvents(
        calendarID: String,
        accessToken: String,
        timeMin: Date,
        timeMax: Date
    ) async throws -> [CalendarEvent] {
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: ISO8601DateFormatter().string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: ISO8601DateFormatter().string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateGoogleResponse(data: data, response: response, context: "events for \(calendarID)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }

        let result = try decoder.decode(EventsListResponse.self, from: data)
        return result.items ?? []
    }

    private func validateGoogleResponse(data: Data, response: URLResponse, context: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.fetchFailed
        }

        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            print("Google Calendar \(context) failed (\(httpResponse.statusCode)): \(message)")

            switch httpResponse.statusCode {
            case 401:
                throw CalendarServiceError.unauthorized(message: message)
            case 403:
                throw CalendarServiceError.forbidden(message: message)
            default:
                throw CalendarServiceError.requestFailed(statusCode: httpResponse.statusCode, message: message)
            }
        }
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data),
           let message = envelope.error.message,
           !message.isEmpty {
            return message
        }

        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body, !body.isEmpty {
            return body
        }

        return "No error body"
    }
}

enum CalendarServiceError: LocalizedError {
    case fetchFailed
    case unauthorized(message: String)
    case forbidden(message: String)
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch calendar data"
        case .unauthorized(let message):
            return "Google Calendar request was unauthorized: \(message)"
        case .forbidden(let message):
            return "Google Calendar access was denied: \(message)"
        case .requestFailed(let statusCode, let message):
            return "Google Calendar request failed (\(statusCode)): \(message)"
        }
    }
}

private struct GoogleAPIErrorEnvelope: Decodable {
    let error: GoogleAPIErrorPayload
}

private struct GoogleAPIErrorPayload: Decodable {
    let message: String?
}
