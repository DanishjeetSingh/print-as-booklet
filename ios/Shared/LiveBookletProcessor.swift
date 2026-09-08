import BookletCore
import Foundation

struct LiveBookletProcessor: BookletProcessing {
    private let client: SubstackClient
    private let renderer: BookletPDFRenderer

    init(
        cookieStorage: HTTPCookieStorage = SharedCookieStore.storage,
        renderer: BookletPDFRenderer = .init()
    ) {
        self.client = SubstackClient(cookieStorage: cookieStorage)
        self.renderer = renderer
    }

    func prepareBooklet(from articleURL: URL) async throws -> PreparedBooklet {
        let downloaded = try await client.downloadPDF(from: articleURL)
        let bookletData = try renderer.render(sourcePDF: downloaded.data)
        let fileURL = try outputURL(for: downloaded.post.postID)
        try bookletData.write(to: fileURL, options: .atomic)
        return PreparedBooklet(fileURL: fileURL, sourcePageCount: downloaded.pageCount)
    }

    private func outputURL(for postID: Int64) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreparedBooklets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("substack-\(postID)-booklet.pdf")
    }
}
