import Foundation

enum PendingArticleStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) ?? .standard
    }

    static func save(_ url: URL) {
        defaults.set(url.absoluteString, forKey: AppConfiguration.pendingArticleURLKey)
    }

    static func take() -> URL? {
        guard let value = defaults.string(forKey: AppConfiguration.pendingArticleURLKey) else {
            return nil
        }
        defaults.removeObject(forKey: AppConfiguration.pendingArticleURLKey)
        return URL(string: value)
    }
}
