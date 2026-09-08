import Foundation
import Testing
@testable import BookletCore

@Test func resolvesPDFEndpointImmediately() throws {
    let url = URL(string: "https://donaldboat.substack.com/api/v1/post/pdf?postId=186391075")!
    let resolved = try SubstackURLResolver.resolveImmediately(url)
    let post = try #require(resolved)
    #expect(post.postID == 186391075)
    #expect(post.pdfURL.absoluteString == url.absoluteString)
}

@Test func extractsPostIDFromServerRenderedData() throws {
    let article = URL(string: "https://donaldboat.substack.com/p/an-essay")!
    let post = try SubstackURLResolver.resolve(
        article,
        articleHTML: #"<script>window._preloads={"post":{"post_id":186391075}}</script>"#
    )
    #expect(post.postID == 186391075)
    #expect(post.pdfURL.absoluteString == "https://donaldboat.substack.com/api/v1/post/pdf?postId=186391075")
}

@Test func rejectsNonSubstackURLs() {
    let url = URL(string: "https://example.com/p/not-substack")!
    #expect(throws: SubstackResolutionError.unsupportedURL) {
        try SubstackURLResolver.resolveImmediately(url)
    }
}
