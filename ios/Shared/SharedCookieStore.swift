import Foundation

enum SharedCookieStore {
    // This is intentionally process-local. A free Personal Team cannot provision
    // App Groups, so the app and Share Extension each maintain their own session.
    static let storage = HTTPCookieStorage.shared

    static func importFromWebKit(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            storage.setCookie(cookie)
        }
    }
}
