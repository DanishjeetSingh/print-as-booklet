import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum State: Equatable {
        case idle
        case ready(URL)
        case preparing
        case prepared(URL, Int)
        case failed(String, URL)
    }

    @Published private(set) var state: State = .idle
    @Published var showingSignIn = false

    private let processor: any BookletProcessing

    init(processor: any BookletProcessing) {
        self.processor = processor
    }

    func handleAppURL(_ url: URL) {
        guard url.scheme == AppConfiguration.callbackScheme else {
            acceptArticleURL(url)
            return
        }
        consumePendingArticle()
    }

    func consumePendingArticle() {
        guard let url = PendingArticleStore.take() else { return }
        acceptArticleURL(url)
    }

    func acceptArticleURL(_ url: URL) {
        state = .ready(url)
    }

    func prepare() async {
        guard case let .ready(url) = state else { return }
        state = .preparing
        do {
            let booklet = try await processor.prepareBooklet(from: url)
            state = .prepared(booklet.fileURL, booklet.sourcePageCount)
        } catch {
            state = .failed(error.localizedDescription, url)
        }
    }

    func retry() async {
        guard case let .failed(_, url) = state else { return }
        state = .ready(url)
        await prepare()
    }

    func reset() {
        state = .idle
    }
}
