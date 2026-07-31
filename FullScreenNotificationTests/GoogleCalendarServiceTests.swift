import Foundation
import XCTest
@testable import FullScreenNotification

@MainActor
final class GoogleCalendarServiceTests: XCTestCase {
    func testUnauthorizedRequestForcesRefreshAndRetriesWithNewToken() async throws {
        let originalToken = OAuthAccessToken(
            value: "original-token",
            expirationDate: Date().addingTimeInterval(-60)
        )
        let refreshedToken = OAuthAccessToken(
            value: "refreshed-token",
            expirationDate: Date().addingTimeInterval(3_600)
        )
        let oauthService = StubOAuthTokenProvider(
            initialToken: originalToken,
            forcedToken: refreshedToken
        )
        let calendarAPI = ScriptedCalendarAPI(statusCodes: [401, 200])
        let service = GoogleCalendarService(
            oauthService: oauthService,
            requestExecutor: { request in
                await calendarAPI.execute(request)
            }
        )

        let events = try await service.fetchUpcomingEvents()

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(oauthService.forceRefreshCalls, [false, true])
        let authorizationHeaders = await calendarAPI.authorizationHeaders
        XCTAssertEqual(
            authorizationHeaders,
            ["Bearer original-token", "Bearer refreshed-token"]
        )
    }

    func testRepeatedUnauthorizedResponseDoesNotRepeatedlyForceRefreshSameToken() async throws {
        let originalToken = OAuthAccessToken(
            value: "original-token",
            expirationDate: Date().addingTimeInterval(-60)
        )
        let refreshedToken = OAuthAccessToken(
            value: "refreshed-token",
            expirationDate: Date().addingTimeInterval(3_600)
        )
        let oauthService = StubOAuthTokenProvider(
            initialToken: originalToken,
            forcedToken: refreshedToken
        )
        let calendarAPI = ScriptedCalendarAPI(statusCodes: [401, 401, 401])
        let service = GoogleCalendarService(
            oauthService: oauthService,
            requestExecutor: { request in
                await calendarAPI.execute(request)
            }
        )

        do {
            _ = try await service.fetchUpcomingEvents()
            XCTFail("Expected the forced-refresh request to remain unauthorized")
        } catch let error as CalendarServiceError {
            XCTAssertTrue(error.isUnauthorized)
        }

        do {
            _ = try await service.fetchUpcomingEvents()
            XCTFail("Expected the next request to remain unauthorized")
        } catch let error as CalendarServiceError {
            XCTAssertTrue(error.isUnauthorized)
        }

        XCTAssertEqual(oauthService.forceRefreshCalls, [false, true, false])
        let authorizationHeaders = await calendarAPI.authorizationHeaders
        XCTAssertEqual(
            authorizationHeaders,
            ["Bearer original-token", "Bearer refreshed-token", "Bearer refreshed-token"]
        )
    }
}

@MainActor
private final class StubOAuthTokenProvider: OAuthAccessTokenProviding {
    private var currentToken: OAuthAccessToken
    private let forcedToken: OAuthAccessToken
    private(set) var forceRefreshCalls: [Bool] = []

    init(initialToken: OAuthAccessToken, forcedToken: OAuthAccessToken) {
        self.currentToken = initialToken
        self.forcedToken = forcedToken
    }

    func freshAccessToken(forceRefresh: Bool) async throws -> OAuthAccessToken {
        forceRefreshCalls.append(forceRefresh)
        if forceRefresh {
            currentToken = forcedToken
        }
        return currentToken
    }
}

private actor ScriptedCalendarAPI {
    private var statusCodes: [Int]
    private(set) var authorizationHeaders: [String] = []

    init(statusCodes: [Int]) {
        self.statusCodes = statusCodes
    }

    func execute(_ request: URLRequest) -> (Data, URLResponse) {
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let statusCode = statusCodes.isEmpty ? 200 : statusCodes.removeFirst()

        let headers = statusCode == 401
            ? ["WWW-Authenticate": "Bearer error=\"invalid_token\""]
            : nil
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        let body = statusCode == 200
            ? #"{"items":[]}"#
            : #"{"error":{"code":401,"message":"Invalid Credentials","status":"UNAUTHENTICATED"}}"#

        return (Data(body.utf8), response)
    }
}
