import Foundation

enum SharedCookieStore {
    static let storage = HTTPCookieStorage.sharedCookieStorage(
        forGroupContainerIdentifier: AppConfiguration.appGroupIdentifier
    )

    static func importFromWebKit(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            storage.setCookie(cookie)
        }
    }
}
