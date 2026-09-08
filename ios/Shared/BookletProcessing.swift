import Foundation

struct PreparedBooklet: Sendable {
    let fileURL: URL
    let sourcePageCount: Int
}

protocol BookletProcessing: Sendable {
    func prepareBooklet(from articleURL: URL) async throws -> PreparedBooklet
}
