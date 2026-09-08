import Foundation
import Network

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

/// A foreground, user-initiated Bonjour browse also lets iOS request the app's
/// local-network permission before Quick Print is used from a share extension.
@MainActor
final class PrinterNetworkStatus: ObservableObject {
    @Published var message = "Allow local network access to use Quick Print from the share panel."
    @Published var searching = false
    @Published var denied = false
    private var browsers: [NWBrowser] = []
    private var timeout: Task<Void, Never>?
    private var discovered = Set<String>()

    func discover() {
        stop()
        denied = false; searching = true; discovered = []
        message = "Looking for printers on your Wi-Fi…"
        for type in ["_ipp._tcp", "_ipps._tcp"] {
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.searching else { return }
                    if case let .waiting(error) = state, case .dns(-65570) = error {
                        self.denied = true
                        self.message = "Enable Local Network in Settings to let Quick Print reach your printer."
                        self.stop()
                    } else if case .failed = state {
                        self.message = "Couldn’t search the local network. Check Wi-Fi and try again."
                        self.stop()
                    }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.searching else { return }
                    for result in results {
                        if case let .service(name, _, _, _) = result.endpoint { self.discovered.insert(name) }
                    }
                    if !self.discovered.isEmpty {
                        self.message = "Available: " + self.discovered.sorted().joined(separator: ", ")
                    }
                }
            }
            browsers.append(browser); browser.start(queue: .main)
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self else { return }
            if discovered.isEmpty {
                message = "No printer found yet. Check that your printer and iPhone use the same Wi-Fi, and allow Local Network in Settings."
            }
            stop()
        }
    }
    func stop() {
        timeout?.cancel(); timeout = nil
        browsers.forEach { $0.cancel() }; browsers = []; searching = false
    }
}
