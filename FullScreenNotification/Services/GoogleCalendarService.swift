import Foundation

@MainActor
final class GoogleCalendarService {
    typealias RequestExecutor = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let oauthService: any OAuthAccessTokenProviding
    private let executeRequest: RequestExecutor
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private var rejectedAccessToken: String?

    init(oauthService: GoogleOAuthService) {
        self.oauthService = oauthService
        self.executeRequest = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(
        oauthService: any OAuthAccessTokenProviding,
        requestExecutor: @escaping RequestExecutor
    ) {
        self.oauthService = oauthService
        self.executeRequest = requestExecutor
    }

    func fetchUpcomingEvents() async throws -> [CalendarEvent] {
        let accessToken = try await oauthService.freshAccessToken(forceRefresh: false)
        let now = Date()

        do {
            let events = try await fetchEvents(
                calendarID: "primary",
                accessToken: accessToken,
                timeMin: now,
                attempt: "initial"
            )
            rejectedAccessToken = nil
            return upcomingEvents(from: events, after: now)
        } catch let error as CalendarServiceError where error.isUnauthorized {
            guard rejectedAccessToken != accessToken.value else {
                AppLogger.error(
                    "calendar.auth",
                    "Google Calendar still rejects the access token obtained by the last forced refresh; " +
                        "keeping the renewable OAuth session and waiting for a later retry"
                )
                throw error
            }

            AppLogger.info(
                "calendar.auth",
                "Google Calendar rejected an access token; forcing one refresh and retry " +
                    tokenTiming(accessToken, at: Date())
            )

            let refreshedToken = try await oauthService.freshAccessToken(forceRefresh: true)

            do {
                let events = try await fetchEvents(
                    calendarID: "primary",
                    accessToken: refreshedToken,
                    timeMin: now,
                    attempt: "after-forced-refresh"
                )
                rejectedAccessToken = nil
                AppLogger.info(
                    "calendar.auth",
                    "Calendar access recovered after forced access-token refresh " +
                        "tokenChanged=\(refreshedToken.value != accessToken.value) " +
                        tokenTiming(refreshedToken, at: Date())
                )
                return upcomingEvents(from: events, after: now)
            } catch let retryError as CalendarServiceError where retryError.isUnauthorized {
                rejectedAccessToken = refreshedToken.value
                AppLogger.error(
                    "calendar.auth",
                    "Google Calendar rejected the forced-refresh access token; " +
                        "keeping the renewable OAuth session instead of disconnecting " +
                        "tokenChanged=\(refreshedToken.value != accessToken.value) " +
                        tokenTiming(refreshedToken, at: Date())
                )
                throw retryError
            }
        }
    }

    private func fetchEvents(
        calendarID: String,
        accessToken: OAuthAccessToken,
        timeMin: Date,
        attempt: String
    ) async throws -> [CalendarEvent] {
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: ISO8601DateFormatter().string(from: timeMin)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken.value)", forHTTPHeaderField: "Authorization")

        let requestStartedAt = Date()
        let (data, response) = try await executeRequest(request)
        try validateGoogleResponse(
            data: data,
            response: response,
            context: "events for \(calendarID)",
            attempt: attempt,
            requestStartedAt: requestStartedAt,
            accessToken: accessToken
        )

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

    private func validateGoogleResponse(
        data: Data,
        response: URLResponse,
        context: String,
        attempt: String,
        requestStartedAt: Date,
        accessToken: OAuthAccessToken
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.error("calendar.api", "Received a non-HTTP response while fetching \(context)")
            throw CalendarServiceError.fetchFailed
        }

        guard httpResponse.statusCode == 200 else {
            let message = parseErrorMessage(from: data)
            let durationMilliseconds = Int(Date().timeIntervalSince(requestStartedAt) * 1_000)
            let requestStarted = ISO8601DateFormatter().string(from: requestStartedAt)
            let authenticateHeader = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate") ?? "none"
            AppLogger.error(
                "calendar.api",
                "Request failed context=\(context) attempt=\(attempt) " +
                    "status=\(httpResponse.statusCode) requestStartedAt=\(requestStarted) " +
                    "durationMs=\(durationMilliseconds) " +
                    "wwwAuthenticate=\(authenticateHeader) " +
                    "\(tokenTiming(accessToken, at: requestStartedAt)) response=\(message)"
            )

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

    private func upcomingEvents(from events: [CalendarEvent], after now: Date) -> [CalendarEvent] {
        events
            .filter { event in
                guard event.canTriggerAlert, let startDate = event.startDate else {
                    return false
                }

                return startDate > now
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private func tokenTiming(_ accessToken: OAuthAccessToken, at date: Date) -> String {
        guard let expirationDate = accessToken.expirationDate else {
            return "accessTokenExpiresAt=unknown secondsUntilExpiration=unknown"
        }

        let expiration = ISO8601DateFormatter().string(from: expirationDate)
        let secondsUntilExpiration = Int(expirationDate.timeIntervalSince(date).rounded())
        return "accessTokenExpiresAt=\(expiration) secondsUntilExpiration=\(secondsUntilExpiration)"
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

    var isUnauthorized: Bool {
        if case .unauthorized = self {
            return true
        }
        return false
    }

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
