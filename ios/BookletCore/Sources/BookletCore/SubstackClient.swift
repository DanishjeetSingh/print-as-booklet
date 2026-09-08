import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PDFKit

public enum SubstackClientError: LocalizedError {
    case invalidHTTPResponse
    case httpFailure(statusCode: Int)
    case loginRequired
    case responseIsNotPDF
    case emptyPDF
    case articleIsNotText

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            "Substack returned an invalid response."
        case let .httpFailure(statusCode):
            "Substack returned HTTP status \(statusCode)."
        case .loginRequired:
            "Sign in to Substack again to retrieve this paid article."
        case .responseIsNotPDF:
            "Substack returned a webpage instead of the article PDF."
        case .emptyPDF:
            "The downloaded PDF contains no pages."
        case .articleIsNotText:
            "The shared Substack article did not return readable page data."
        }
    }
}

public struct SubstackPDF: @unchecked Sendable {
    public let post: ResolvedSubstackPost
    public let data: Data
    public let pageCount: Int
}

public final class SubstackClient: @unchecked Sendable {
    private let session: URLSession

    /// Use a persistent `WKWebsiteDataStore` cookie store in the app, then copy its
    /// cookies into this session's `HTTPCookieStorage` before resolving a post.
    public init(cookieStorage: HTTPCookieStorage = .shared) {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
        ]
        self.session = URLSession(configuration: configuration)
    }

    public init(session: URLSession) {
        self.session = session
    }

    /// Confirms that the session belongs to a signed-in Substack account before
    /// accepting a PDF. This prevents Substack's valid-but-shortened public
    /// preview PDF from being mistaken for the complete paid article.
    public func verifyAuthentication() async throws {
        let profileURL = URL(string: "https://substack.com/api/v1/user/profile/self")!
        var request = URLRequest(url: profileURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await session.data(for: request)
        try Self.validateHTTP(response)
    }

    public func resolvePost(from sharedURL: URL) async throws -> ResolvedSubstackPost {
        if let immediate = try SubstackURLResolver.resolveImmediately(sharedURL) {
            return immediate
        }

        let (data, response) = try await session.data(from: sharedURL)
        try Self.validateHTTP(response)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SubstackClientError.articleIsNotText
        }
        let finalURL = response.url ?? sharedURL
        return try SubstackURLResolver.resolve(finalURL, articleHTML: html)
    }

    public func downloadPDF(from sharedURL: URL) async throws -> SubstackPDF {
        try await verifyAuthentication()
        let post = try await resolvePost(from: sharedURL)
        return try await downloadPDF(for: post)
    }

    public func downloadPDF(for post: ResolvedSubstackPost) async throws -> SubstackPDF {
        var request = URLRequest(url: post.pdfURL)
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        request.setValue(post.articleURL.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubstackClientError.invalidHTTPResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SubstackClientError.loginRequired
        }
        try Self.validateHTTP(http)

        let header = data.prefix(1024)
        guard header.range(of: Data("%PDF-".utf8)) != nil else {
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("text/html") {
                throw SubstackClientError.loginRequired
            }
            throw SubstackClientError.responseIsNotPDF
        }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw SubstackClientError.emptyPDF
        }
        return SubstackPDF(post: post, data: data, pageCount: document.pageCount)
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SubstackClientError.invalidHTTPResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw SubstackClientError.loginRequired
            }
            throw SubstackClientError.httpFailure(statusCode: http.statusCode)
        }
    }
}
