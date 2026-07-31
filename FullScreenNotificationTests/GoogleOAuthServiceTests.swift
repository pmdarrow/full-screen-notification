@preconcurrency import AppAuth
import XCTest
@testable import FullScreenNotification

@MainActor
final class GoogleOAuthServiceTests: XCTestCase {
    func testInvalidGrantMeansGoogleRejectedRefreshToken() {
        let error = oauthTokenError(code: "invalid_grant")

        XCTAssertTrue(GoogleOAuthService.refreshTokenWasRejected(error))
    }

    func testOtherTokenEndpointErrorPreservesRefreshToken() {
        let error = oauthTokenError(code: "temporarily_unavailable")

        XCTAssertFalse(GoogleOAuthService.refreshTokenWasRejected(error))
    }

    private func oauthTokenError(code: String) -> NSError {
        NSError(
            domain: OIDOAuthTokenErrorDomain,
            code: 0,
            userInfo: [
                OIDOAuthErrorResponseErrorKey: [
                    OIDOAuthErrorFieldError: code,
                ],
            ]
        )
    }
}
