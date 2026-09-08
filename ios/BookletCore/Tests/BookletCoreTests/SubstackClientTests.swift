import Foundation
import Testing
@testable import BookletCore

@Test func fallsBackToPublicationSlugAPI() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockSubstackURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = SubstackClient(session: session)

    let post = try await client.resolvePost(
        from: URL(string: "https://publication.substack.com/p/a-paid-essay")!
    )

    #expect(post.postID == 186391075)
    #expect(post.articleURL.absoluteString == "https://publication.substack.com/p/a-paid-essay")
    #expect(MockSubstackURLProtocol.requestedPaths == [
        "/p/a-paid-essay",
        "/api/v1/posts/a-paid-essay",
    ])
}

@Test func readerPathIDUsesByIDCanonicalURLForPDFEndpoint() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockReaderRedirectURLProtocol.self]
    let client = SubstackClient(session: URLSession(configuration: configuration))

    let post = try await client.resolvePost(
        from: URL(string: "https://substack.com/home/post/p-186391075")!
    )

    #expect(post.postID == 186391075)
    #expect(post.pdfURL.absoluteString == "https://publication.substack.com/api/v1/post/pdf?postId=186391075")
}

private final class MockSubstackURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestedPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requestedPaths.append(url.path)

        let body: Data
        let contentType: String
        if url.path == "/api/v1/posts/a-paid-essay" {
            body = Data(#"{"id":186391075}"#.utf8)
            contentType = "application/json"
        } else {
            body = Data("<html><body>Article without embedded metadata</body></html>".utf8)
            contentType = "text/html"
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class MockReaderRedirectURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let requestURL = request.url!
        let body: Data
        if requestURL.path == "/api/v1/posts/by-id/186391075" {
            body = Data(#"{"post":{"canonical_url":"https://publication.substack.com/p/a-paid-essay"}}"#.utf8)
        } else {
            body = Data("<html></html>".utf8)
        }
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": requestURL.path.hasPrefix("/api/") ? "application/json" : "text/html"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
