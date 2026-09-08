import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum AuthenticationState: Equatable {
        case unknown
        case verifying
        case signedIn
        case failed(String)
    }

    enum State: Equatable {
        case idle
        case ready(URL)
        case preparing
        case prepared(URL, Int)
        case failed(String, URL)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var authenticationState: AuthenticationState = .unknown
    @Published var showingSignIn = false

    private let processor: any BookletProcessing

    init(processor: any BookletProcessing) {
        self.processor = processor
    }

    func acceptArticleURL(_ url: URL) {
        state = .ready(url)
    }

    func finishSignIn() async {
        authenticationState = .verifying
        do {
            try await processor.verifyAuthentication()
            authenticationState = .signedIn
        } catch {
            authenticationState = .failed(
                "Sign-in could not be confirmed: \(error.localizedDescription)"
            )
        }
        showingSignIn = false
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
