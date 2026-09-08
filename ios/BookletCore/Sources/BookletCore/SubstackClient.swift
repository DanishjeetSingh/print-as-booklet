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
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
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
        let immediate = try SubstackURLResolver.resolveImmediately(sharedURL)
        if let immediate {
            if let canonical = try? await canonicalPost(for: immediate.postID) {
                return canonical
            }
            if !Self.isCentralReaderURL(sharedURL) {
                return immediate
            }
        }

        let (data, response) = try await session.data(from: sharedURL)
        try Self.validateHTTP(response)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SubstackClientError.articleIsNotText
        }
        let finalURL = response.url ?? sharedURL
        if let immediate {
            // Reader links such as substack.com/home/post/p-123 redirect to the
            // publication. The PDF endpoint exists on that publication host,
            // not on the central reader host.
            try SubstackURLResolver.validateSubstackURL(finalURL)
            return ResolvedSubstackPost(articleURL: finalURL, postID: immediate.postID)
        }
        do {
            let resolved = try SubstackURLResolver.resolve(finalURL, articleHTML: html)
            return (try? await canonicalPost(for: resolved.postID)) ?? resolved
        } catch SubstackResolutionError.postIDNotFound {
            guard let slug = Self.articleSlug(from: finalURL) else {
                throw SubstackResolutionError.postIDNotFound
            }
            return try await resolvePostFromPublicationAPI(articleURL: finalURL, slug: slug)
        }
    }

    public func downloadPDF(from sharedURL: URL) async throws -> SubstackPDF {
        let post = try await resolvePost(from: sharedURL)
        if !post.isPublic {
            try await verifyAuthentication()
        }
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

    private func resolvePostFromPublicationAPI(
        articleURL: URL,
        slug: String
    ) async throws -> ResolvedSubstackPost {
        guard var components = URLComponents(url: articleURL, resolvingAgainstBaseURL: false) else {
            throw SubstackResolutionError.postIDNotFound
        }
        components.path = "/api/v1/posts"
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else {
            throw SubstackResolutionError.postIDNotFound
        }
        let endpoint = baseURL.appendingPathComponent(slug)
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(articleURL.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        try Self.validateHTTP(response)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let postID = Self.postID(from: object),
            postID > 0
        else {
            throw SubstackResolutionError.postIDNotFound
        }
        return ResolvedSubstackPost(
            articleURL: articleURL,
            postID: postID,
            audience: object["audience"] as? String
        )
    }

    private func canonicalPost(for postID: Int64) async throws -> ResolvedSubstackPost {
        let endpoint = URL(string: "https://substack.com/api/v1/posts/by-id/\(postID)")!
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.validateHTTP(response)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let post = object["post"] as? [String: Any],
            let canonicalString = post["canonical_url"] as? String,
            let canonicalURL = URL(string: canonicalString),
            let scheme = canonicalURL.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            canonicalURL.host != nil
        else {
            throw SubstackResolutionError.postIDNotFound
        }
        return ResolvedSubstackPost(
            articleURL: canonicalURL,
            postID: postID,
            audience: post["audience"] as? String
        )
    }

    private static func articleSlug(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard
            let marker = components.lastIndex(where: { $0.lowercased() == "p" }),
            components.indices.contains(marker + 1)
        else { return nil }
        let slug = components[marker + 1]
        return slug.isEmpty ? nil : slug
    }

    private static func isCentralReaderURL(_ url: URL) -> Bool {
        guard url.host?.lowercased() == "substack.com" else { return false }
        return url.path.lowercased().hasPrefix("/home/post/")
    }

    private static func postID(from object: [String: Any]) -> Int64? {
        for key in ["id", "post_id", "postId"] {
            switch object[key] {
            case let value as NSNumber:
                return value.int64Value
            case let value as String:
                return Int64(value)
            default:
                continue
            }
        }
        return nil
    }
}
