import Foundation

enum Constants {
    // MARK: - Google OAuth

    static let googleClientID: String = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as! String
    static let googleClientSecret: String = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as! String
    static let googleCalendarReadonlyScope = "https://www.googleapis.com/auth/calendar.readonly"
}
