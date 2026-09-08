import BookletCore
import Social
import UniformTypeIdentifiers
import UIKit
import WebKit

final class ShareViewController: SLComposeServiceViewController {
    private var articleURL: URL?
    private let processor: any BookletProcessing = LiveBookletProcessor()
    private let quickPrinter = IPPPrintClient()

    private enum PrinterDefaults {
        static let url = "quickPrinterURL"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Print as Booklet"
        placeholder = "The article will be prepared here."
        loadSharedURL()
    }

    override func isContentValid() -> Bool {
        articleURL != nil
    }

    override func didSelectPost() {
        guard let articleURL else {
            extensionContext?.cancelRequest(withError: ShareError.noURL)
            return
        }
        prepareAndPrint(articleURL)
    }

    override func configurationItems() -> [Any]! { [] }

    private func loadSharedURL() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var providers: [NSItemProvider] = []
        for item in items {
            providers.append(contentsOf: item.attachments ?? [])
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) else {
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            let url = item as? URL ?? (item as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                self?.articleURL = url
                self?.validateContent()
            }
        }
    }

    private func prepareAndPrint(_ url: URL) {
        setWorking(true, title: "Preparing…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let booklet = try await processor.prepareBooklet(from: url)
                quickPrintOrChoosePrinter(fileURL: booklet.fileURL)
            } catch {
                handlePreparationError(error, articleURL: url)
            }
        }
    }

    private func quickPrintOrChoosePrinter(fileURL: URL) {
        guard
            let saved = UserDefaults.standard.string(forKey: PrinterDefaults.url),
            let printerURL = URL(string: saved)
        else {
            presentPrintSheet(for: fileURL, rememberPrinter: true)
            return
        }
        submitQuickPrint(fileURL: fileURL, to: UIPrinter(url: printerURL))
    }

    private func submitQuickPrint(fileURL: URL, to printer: UIPrinter) {
        setWorking(true, title: "Printing…")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await quickPrinter.printBooklet(at: fileURL, to: printer.url)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                setWorking(false, title: "Print as Booklet")
                showQuickPrintError(error, fileURL: fileURL)
            }
        }
    }

    private func showQuickPrintError(_ error: Error, fileURL: URL?) {
        let alert = UIAlertController(
            title: "Quick Print Failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        if let fileURL {
            alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
                self?.quickPrintOrChoosePrinter(fileURL: fileURL)
            })
            alert.addAction(UIAlertAction(title: "Change Printer", style: .default) { [weak self] _ in
                UserDefaults.standard.removeObject(forKey: PrinterDefaults.url)
                self?.presentPrintSheet(for: fileURL, rememberPrinter: true)
            })
            alert.addAction(UIAlertAction(title: "Standard Print", style: .default) { [weak self] _ in
                self?.presentPrintSheet(for: fileURL, rememberPrinter: true)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func handlePreparationError(_ error: Error, articleURL: URL) {
        setWorking(false, title: "Print as Booklet")
        if requiresSignIn(error) {
            presentSignInThenRetry(articleURL)
            return
        }

        let alert = UIAlertController(
            title: "Couldn’t Prepare Booklet",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.prepareAndPrint(articleURL)
        })
        alert.addAction(UIAlertAction(title: "Sign In", style: .default) { [weak self] _ in
            self?.presentSignInThenRetry(articleURL)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func requiresSignIn(_ error: Error) -> Bool {
        guard let clientError = error as? SubstackClientError else { return false }
        if case .loginRequired = clientError { return true }
        return false
    }

    private func presentSignInThenRetry(_ articleURL: URL) {
        let signIn = ExtensionSignInViewController { [weak self] completed in
            guard let self else { return }
            if completed {
                prepareAndPrint(articleURL)
            } else {
                setWorking(false, title: "Print as Booklet")
            }
        }
        let navigation = UINavigationController(rootViewController: signIn)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func presentPrintSheet(for fileURL: URL, rememberPrinter: Bool = false) {
        setWorking(false, title: "Print Booklet")

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Booklet"
        info.outputType = .general
        info.duplex = .longEdge

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = fileURL
        let presented = controller.present(animated: true) { [weak self] controller, completed, _ in
            if rememberPrinter, completed, let printerID = controller.printInfo?.printerID {
                UserDefaults.standard.set(printerID, forKey: PrinterDefaults.url)
            }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        if !presented {
            showPrintPresentationError()
        }
    }

    private func showPrintPresentationError() {
        let alert = UIAlertController(
            title: "Couldn’t Open AirPrint",
            message: "Close this panel and share the article again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func setWorking(_ working: Bool, title: String) {
        self.title = title
        navigationItem.rightBarButtonItem?.isEnabled = !working
        view.isUserInteractionEnabled = !working
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
