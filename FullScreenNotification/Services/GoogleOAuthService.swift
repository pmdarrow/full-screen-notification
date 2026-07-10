import AppKit
@preconcurrency import AppAuth
import Foundation

@MainActor
final class GoogleOAuthService {
    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let storedEmailKey = "googleOAuthEmail"

    private let credentialStore = OAuthCredentialStore()
    private var authState: OIDAuthState?
    private var redirectHTTPHandler: OIDRedirectHTTPHandler?
    private var presentationWindow: NSWindow?

    private(set) var isAuthenticated = false
    private(set) var currentUserEmail: String?

    init() {
        currentUserEmail = UserDefaults.standard.string(forKey: Self.storedEmailKey)
    }

    var accessToken: String? {
        authState?.lastTokenResponse?.accessToken
    }

    var hasCalendarAccess: Bool {
        guard let scope = authState?.scope else { return false }
        return scope
            .split(whereSeparator: \.isWhitespace)
            .contains(Substring(Constants.googleCalendarReadonlyScope))
    }

    func restorePreviousSignIn() async {
        do {
            guard let restoredState = try credentialStore.load() else {
                clearSession()
                return
            }

            authState = restoredState
            if currentUserEmail == nil {
                currentUserEmail = emailAddress(from: restoredState)
            }
            isAuthenticated = restoredState.isAuthorized && hasCalendarAccess
        } catch {
            print("Could not restore Google OAuth session: \(error.localizedDescription)")
            clearSession()
        }
    }

    func startSignIn(presentingWindow: NSWindow?) async throws {
        let createdPresentationWindow = presentingWindow == nil
        let window = presentingWindow ?? makePresentationWindow()

        if createdPresentationWindow {
            presentationWindow = window
        }

        defer {
            stopRedirectListener()
            if createdPresentationWindow, presentationWindow === window {
                window.close()
                presentationWindow = nil
            }
        }

        let handler = OIDRedirectHTTPHandler(successURL: nil)
        var listenerError: NSError?
        let redirectURL = handler.startHTTPListener(&listenerError)
        if let listenerError {
            throw OAuthError.sdkError(
                message: listenerError.localizedDescription
            )
        }

        redirectHTTPHandler = handler

        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: Self.authorizationEndpoint,
            tokenEndpoint: Self.tokenEndpoint
        )
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: Constants.googleClientID,
            clientSecret: nil,
            scopes: [OIDScopeOpenID, OIDScopeEmail, Constants.googleCalendarReadonlyScope],
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["access_type": "offline"]
        )

        let signedInState: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            let flow = OIDAuthState.authState(
                byPresenting: request,
                presenting: window
            ) { state, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let state else {
                    continuation.resume(
                        throwing: OAuthError.sdkError(message: "Google returned no authorization session.")
                    )
                    return
                }

                continuation.resume(returning: state)
            }
            handler.currentAuthorizationFlow = flow
        }

        authState = signedInState
        currentUserEmail = emailAddress(from: signedInState)

        guard hasCalendarAccess else {
            isAuthenticated = false
            throw OAuthError.calendarPermissionNotGranted
        }

        do {
            try credentialStore.save(signedInState)
        } catch {
            clearSession()
            throw OAuthError.sdkError(message: "The Google session couldn't be saved in Keychain: \(error.localizedDescription)")
        }

        UserDefaults.standard.set(currentUserEmail, forKey: Self.storedEmailKey)
        isAuthenticated = true
    }

    func refreshTokenIfNeeded() async throws {
        guard let authState else {
            throw OAuthError.notAuthenticated
        }
        guard hasCalendarAccess else {
            isAuthenticated = false
            throw OAuthError.calendarPermissionNotGranted
        }

        let token: String = try await withCheckedThrowingContinuation { continuation in
            authState.performAction { accessToken, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let accessToken else {
                    continuation.resume(throwing: OAuthError.notAuthenticated)
                    return
                }

                continuation.resume(returning: accessToken)
            }
        }

        guard !token.isEmpty else {
            throw OAuthError.notAuthenticated
        }

        do {
            try credentialStore.save(authState)
        } catch {
            throw OAuthError.sdkError(message: "The refreshed Google session couldn't be saved: \(error.localizedDescription)")
        }

        isAuthenticated = authState.isAuthorized
    }

    func signOut() {
        stopRedirectListener()
        clearSession()
    }

    private func stopRedirectListener() {
        redirectHTTPHandler?.currentAuthorizationFlow = nil
        redirectHTTPHandler?.cancelHTTPListener()
        redirectHTTPHandler = nil
    }

    private func clearSession() {
        try? credentialStore.delete()
        authState = nil
        isAuthenticated = false
        currentUserEmail = nil
        UserDefaults.standard.removeObject(forKey: Self.storedEmailKey)
    }

    private func emailAddress(from authState: OIDAuthState) -> String? {
        guard let idTokenString = authState.lastTokenResponse?.idToken,
              let idToken = OIDIDToken(idTokenString: idTokenString) else {
            return nil
        }

        return idToken.claims["email"] as? String
    }

    private func makePresentationWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0.01
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

enum OAuthError: LocalizedError {
    case notAuthenticated
    case canceled
    case calendarPermissionNotGranted
    case sdkError(message: String)

    init(from error: Error) {
        if let oauthError = error as? OAuthError {
            self = oauthError
            return
        }

        let nsError = error as NSError
        if nsError.domain == OIDGeneralErrorDomain &&
            (nsError.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue ||
             nsError.code == OIDErrorCode.programCanceledAuthorizationFlow.rawValue) {
            self = .canceled
        } else {
            self = .sdkError(message: nsError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .canceled:
            return "Google sign-in was canceled."
        case .calendarPermissionNotGranted:
            return "Calendar access was not granted. Sign in again and keep Google Calendar enabled."
        case .sdkError(let message):
            return message
        }
    }
}
