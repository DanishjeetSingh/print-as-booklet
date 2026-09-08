import Foundation

public enum SubstackResolutionError: LocalizedError, Equatable {
    case unsupportedURL
    case postIDNotFound
    case invalidPostID

    public var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "Share a substack.com article or PDF URL."
        case .postIDNotFound:
            "The Substack post ID could not be found in the shared article."
        case .invalidPostID:
            "The shared URL contains an invalid Substack post ID."
        }
    }
}

public struct ResolvedSubstackPost: Sendable, Equatable {
    public let articleURL: URL
    public let postID: Int64
    public let audience: String?

    public init(articleURL: URL, postID: Int64, audience: String? = nil) {
        self.articleURL = articleURL
        self.postID = postID
        self.audience = audience
    }

    public var isPublic: Bool { audience?.lowercased() == "everyone" }

    public var pdfURL: URL {
        var components = URLComponents()
        components.scheme = articleURL.scheme ?? "https"
        components.host = articleURL.host
        components.path = "/api/v1/post/pdf"
        components.queryItems = [URLQueryItem(name: "postId", value: String(postID))]
        // Construction starts from a validated HTTP(S) Substack URL, so this is safe.
        return components.url!
    }
}

public enum SubstackURLResolver {
    /// Resolves URLs which already carry a post ID, including Substack PDF endpoints.
    public static func resolveImmediately(_ url: URL) throws -> ResolvedSubstackPost? {
        try validateSubstackURL(url)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SubstackResolutionError.unsupportedURL
        }

        for item in components.queryItems ?? [] where item.name.lowercased() == "postid" {
            guard let value = item.value, let postID = Int64(value), postID > 0 else {
                throw SubstackResolutionError.invalidPostID
            }
            return ResolvedSubstackPost(articleURL: canonicalArticleURL(url), postID: postID)
        }

        let pathIDPattern = try NSRegularExpression(
            pattern: #"^p-(\d+)$"#,
            options: [.caseInsensitive]
        )
        for component in url.pathComponents {
            let range = NSRange(component.startIndex..., in: component)
            guard
                let match = pathIDPattern.firstMatch(in: component, range: range),
                let captureRange = Range(match.range(at: 1), in: component),
                let postID = Int64(component[captureRange]),
                postID > 0
            else { continue }
            return ResolvedSubstackPost(articleURL: canonicalArticleURL(url), postID: postID)
        }
        return nil
    }

    /// Extracts the post ID from Substack's server-rendered page data.
    public static func resolve(_ url: URL, articleHTML: String) throws -> ResolvedSubstackPost {
        if let immediate = try resolveImmediately(url) {
            return immediate
        }

        let patterns = [
            #"[\"']postId[\"']\s*:\s*[\"']?(\d+)[\"']?"#,
            #"[\"']post_id[\"']\s*:\s*[\"']?(\d+)[\"']?"#,
            #"postId(?:%22|&quot;|\\u0022)?\s*(?::|%3A)\s*(?:%22|&quot;|\\u0022)?(\d+)"#,
        ]

        for candidate in HTMLCandidates(articleHTML) {
            for pattern in patterns {
                let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(candidate.startIndex..., in: candidate)
                guard
                    let match = expression.firstMatch(in: candidate, range: range),
                    let captureRange = Range(match.range(at: 1), in: candidate),
                    let postID = Int64(candidate[captureRange]),
                    postID > 0
                else { continue }

                return ResolvedSubstackPost(articleURL: canonicalArticleURL(url), postID: postID)
            }
        }

        throw SubstackResolutionError.postIDNotFound
    }

    public static func validateSubstackURL(_ url: URL) throws {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = url.host?.lowercased(),
            host == "substack.com" || host.hasSuffix(".substack.com")
        else {
            throw SubstackResolutionError.unsupportedURL
        }
    }

    private static func canonicalArticleURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }

    private static func HTMLCandidates(_ html: String) -> [String] {
        var decoded = html
        for _ in 0..<2 {
            decoded = decoded
                .replacingOccurrences(of: #"\""#, with: #"""#)
                .replacingOccurrences(of: #"\u0022"#, with: #"""#, options: [.caseInsensitive])
                .replacingOccurrences(of: "&quot;", with: #"""#, options: [.caseInsensitive])
                .replacingOccurrences(of: "%22", with: #"""#, options: [.caseInsensitive])
                .replacingOccurrences(of: "%3A", with: ":", options: [.caseInsensitive])
        }
        return decoded == html ? [html] : [html, decoded]
    }
}
