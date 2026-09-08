import Foundation

struct PreparedBooklet: Sendable {
    let fileURL: URL
    let sourcePageCount: Int
}

protocol BookletProcessing: Sendable {
    func verifyAuthentication() async throws
    func prepareBooklet(from articleURL: URL) async throws -> PreparedBooklet
}
