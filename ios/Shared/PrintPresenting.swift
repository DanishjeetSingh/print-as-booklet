import Foundation

@MainActor
protocol PrintPresenting {
    func presentPrintSheet(for fileURL: URL, jobName: String)
}
