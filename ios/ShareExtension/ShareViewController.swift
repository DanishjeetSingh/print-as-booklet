import BookletCore
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WebKit

@MainActor
private final class SharePanelState: ObservableObject {
    @Published var articleURL: URL?
    @Published var heading = "Opening article…"
    @Published var detail = "Reading the shared link."
    @Published var busy = true
    @Published var prepared = false
    @Published var sent = false
    @Published var failed = false
    @Published var pageCount: Int?
    @Published var printerName: String?
}

final class ShareViewController: UIViewController {
    private let panel = SharePanelState()
    private let processor: any BookletProcessing = LiveBookletProcessor()
    private let quickPrinter = IPPPrintClient()
    private let resolver = PrinterAddressResolver()
    private var preparedURL: URL?
    private var operation: Task<Void, Never>?
    private let printerKey = "quickPrinterURL"

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 540, height: 600)
        let root = SharePanel(state: panel, primary: { [weak self] in self?.performPrimary() },
                              standard: { [weak self] in self?.standardPrint() },
                              close: { [weak self] in self?.finish() })
        let host = UIHostingController(rootView: root)
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        refreshPrinterName()
        loadSharedURL()
    }

    private func refreshPrinterName() {
        guard let saved = UserDefaults.standard.string(forKey: printerKey) else { panel.printerName = nil; return }
        panel.printerName = BonjourPrinterAddress(saved)?.name ?? URL(string: saved)?.host ?? "Saved printer"

    }

    private func loadSharedURL() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
            showFailure(ShareError.noURL.localizedDescription); return
        }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            let url = item as? URL ?? (item as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                guard let self else { return }
                guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    self.showFailure(error?.localizedDescription ?? ShareError.noURL.localizedDescription); return
                }
                self.panel.articleURL = url
                self.panel.busy = false
                self.panel.heading = "Ready to make\na booklet."
                self.panel.detail = "Pages arranged, numbered, and ready to fold."
            }
        }
    }

    private func performPrimary() {
        guard !panel.busy else { return }
        if panel.sent { finish(); return }
        if let preparedURL { quickPrintOrChoosePrinter(fileURL: preparedURL); return }
        guard let url = panel.articleURL else { return }
        setWorking("Preparing booklet…", detail: "Downloading the article and arranging the pages.")
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let booklet = try await processor.prepareBooklet(from: url)
                preparedURL = booklet.fileURL
                panel.pageCount = booklet.sourcePageCount; panel.prepared = true
                quickPrintOrChoosePrinter(fileURL: booklet.fileURL)
            } catch {
                panel.busy = false
                if let error = error as? SubstackClientError, case .loginRequired = error { presentSignInThenRetry() }
                else { showFailure(error.localizedDescription) }
            }
        }
    }

    private func quickPrintOrChoosePrinter(fileURL: URL) {
        guard let saved = UserDefaults.standard.string(forKey: printerKey) else {
            presentPrintSheet(for: fileURL); return
        }
        setWorking("Finding printer…", detail: "Connecting to your saved printer on Wi-Fi.")
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let endpoint = try await resolver.resolve(saved)
                let receipt = try await quickPrinter.printBooklet(at: fileURL, to: endpoint) { [panel] message in
                    await MainActor.run { panel.heading = message }
                }
                panel.busy = false; panel.sent = true; panel.failed = false
                panel.heading = "Sent to printer."
                panel.detail = receipt.jobID.map { "Job \($0) was accepted. Fold the sheets through the middle, then staple along the guide." }
                    ?? "The printer accepted your booklet. Fold the sheets through the middle, then staple along the guide."
            } catch { showFailure(error.localizedDescription) }
        }
    }

    private func standardPrint() {
        guard let preparedURL, !panel.busy else { return }
        presentPrintSheet(for: preparedURL)
    }

    private func presentPrintSheet(for fileURL: URL) {
        panel.busy = false; panel.failed = false
        panel.heading = "Your booklet is ready."
        panel.detail = "Choose your printer in AirPrint. After the first successful print, Quick Print remembers it."
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Booklet"; info.outputType = .general; info.duplex = .longEdge
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info; controller.printingItem = fileURL
        let completion: UIPrintInteractionController.CompletionHandler = { [weak self] controller, completed, error in
            guard let self else { return }
            if let error { showFailure(error.localizedDescription); return }
            guard completed else {
                panel.detail = "Printing was cancelled. Your prepared booklet is still ready."
                return
            }
            if let printerID = controller.printInfo?.printerID,
               BonjourPrinterAddress(printerID) != nil || URL(string: printerID)?.host != nil {
                UserDefaults.standard.set(printerID, forKey: printerKey)
                refreshPrinterName()
            }
            panel.sent = true; panel.heading = "Sent to printer."
            panel.detail = "Fold through the middle and staple along the guide. This printer is saved for next time."
        }
        let presented: Bool
        if traitCollection.userInterfaceIdiom == .pad {
            presented = controller.present(from: CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1), in: view, animated: true, completionHandler: completion)
        } else { presented = controller.present(animated: true, completionHandler: completion) }
        if !presented { showFailure("AirPrint could not open. Your booklet is ready; tap Standard Print to try again.") }
    }

    private func presentSignInThenRetry() {
        panel.heading = "Sign in to continue."
        panel.detail = "This article requires your Substack subscription."
        let signIn = ExtensionSignInViewController { [weak self] completed in
            if completed { self?.performPrimary() }
        }
        let navigation = UINavigationController(rootViewController: signIn)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func setWorking(_ heading: String, detail: String) {
        panel.busy = true; panel.failed = false; panel.heading = heading; panel.detail = detail
    }
    private func showFailure(_ message: String) {
        panel.busy = false; panel.failed = true
        panel.heading = preparedURL == nil ? "Couldn’t prepare booklet." : "Printing needs attention."
        panel.detail = message
    }
    private func finish() {
        guard !panel.busy else { return }
        if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct SharePanel: View {
    @ObservedObject var state: SharePanelState
    let primary: () -> Void
    let standard: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var tint: Color { colorScheme == .dark ? Color(red: 0.55, green: 0.78, blue: 0.64) : Color(red: 0.10, green: 0.23, blue: 0.18) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("PRINT AS BOOKLET").font(.caption.weight(.semibold)).tracking(2)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").font(.caption.bold()).padding(10).background(.quaternary, in: Circle()) }
                        .disabled(state.busy).accessibilityLabel("Close")
                }
                HStack(alignment: .center, spacing: 18) {
                    Image("BookletMark").resizable().frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.heading).font(.system(.title2, design: .serif)).fixedSize(horizontal: false, vertical: true)
                        if state.busy { ProgressView().controlSize(.small) }
                        else if state.sent { Label("Job accepted", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(tint) }
                    }
                }
                Text(state.detail).font(.subheadline).foregroundStyle(state.failed ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    if let url = state.articleURL {
                        Label { Text(url.host ?? "Article").font(.subheadline.weight(.medium)) } icon: { Image(systemName: "doc.text") }
                        Text(url.path.removingPercentEncoding ?? url.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Divider()
                    }
                    HStack {
                        Label("Letter · Two-sided", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        Spacer()
                        if let count = state.pageCount { Text("\((count + 3) / 4) sheets") }
                    }.font(.caption).foregroundStyle(.secondary)
                    Label(state.printerName ?? "Choose printer on first print", systemImage: "printer")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                VStack(spacing: 14) {
                    Button(action: primary) {
                        HStack {
                            Spacer()
                            if state.busy { ProgressView().tint(.white) }
                            Text(state.sent ? "Done" : state.busy ? "Working…" : state.failed ? "Try again" : state.prepared ? "Print booklet" : "Prepare & print")
                            if !state.busy && !state.sent { Image(systemName: "arrow.right") }
                            Spacer()
                        }.font(.headline).padding(.vertical, 9)
                    }.buttonStyle(.borderedProminent).disabled(state.busy || state.articleURL == nil)
                    if state.prepared && !state.sent {
                        Button("Standard Print / Change Printer", action: standard).font(.subheadline).disabled(state.busy)
                    }
                }
            }.padding(26).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(colorScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Color(red: 0.96, green: 0.95, blue: 0.92))
        .tint(tint)
    }
}
private final class ExtensionSignInViewController: UIViewController {
    private let completion: (Bool) -> Void
    private let webView: WKWebView
    private var finished = false

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Substack Sign In"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(done)
        )

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView.load(URLRequest(url: AppConfiguration.substackSignInURL))
    }

    @objc private func done() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                SharedCookieStore.importFromWebKit(cookies)
                self.finished = true
                self.dismiss(animated: true) { self.completion(true) }
            }
        }
    }

    @objc private func cancel() {
        guard !finished else { return }
        finished = true
        dismiss(animated: true) { self.completion(false) }
    }
}

enum ShareError: LocalizedError {
    case noURL

    var errorDescription: String? { "The shared item did not contain an article URL." }
}
