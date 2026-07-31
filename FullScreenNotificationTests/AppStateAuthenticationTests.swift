import XCTest
@testable import FullScreenNotification

@MainActor
final class AppStateAuthenticationTests: XCTestCase {
    func testCalendarUnauthorizedKeepsRenewableSession() {
        let error = CalendarServiceError.unauthorized(message: "Invalid Credentials")

        XCTAssertFalse(AppState.requiresReauthentication(after: error))
    }

    func testRejectedRefreshTokenRequiresReauthentication() {
        let error = OAuthError.sessionExpired(message: "invalid_grant")

        XCTAssertTrue(AppState.requiresReauthentication(after: error))
    }
}
