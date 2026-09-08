import Social
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: SLComposeServiceViewController {
    private var articleURL: URL?
    private let processor: any BookletProcessing = LiveBookletProcessor()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Print as Booklet"
        placeholder = "The article will be prepared in Print as Booklet."
        loadSharedURL()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.rightBarButtonItem?.title = "Print"
    }

    override func isContentValid() -> Bool {
        articleURL != nil
    }

    override func didSelectPost() {
        guard let articleURL else {
            extensionContext?.cancelRequest(withError: ShareError.noURL)
            return
        }

        title = "Preparing…"
        navigationItem.rightBarButtonItem?.isEnabled = false
        view.isUserInteractionEnabled = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let booklet = try await processor.prepareBooklet(from: articleURL)
                presentPrintSheet(for: booklet.fileURL)
            } catch {
                queueForContainingApp(articleURL, reason: error.localizedDescription)
            }
        }
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

    private func presentPrintSheet(for fileURL: URL) {
        title = "Print Booklet"
        view.isUserInteractionEnabled = true

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Booklet"
        info.outputType = .general
        info.duplex = .shortEdge

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = fileURL
        let presented = controller.present(animated: true) { [weak self] _, _, _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        if !presented {
            queueForContainingApp(
                articleURL,
                reason: "AirPrint could not open inside the share window."
            )
        }
    }

    private func queueForContainingApp(_ url: URL?, reason: String) {
        guard let url else {
            extensionContext?.cancelRequest(withError: ShareError.noURL)
            return
        }
        PendingArticleStore.save(url)
        let callback = URL(string: "\(AppConfiguration.callbackScheme)://shared-article")!
        extensionContext?.open(callback) { [weak self] opened in
            guard let self else { return }
            if opened {
                extensionContext?.completeRequest(returningItems: nil)
                return
            }

            let alert = UIAlertController(
                title: "Continue in Print as Booklet",
                message: "\(reason) Open the Print as Booklet app to continue this saved article.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            present(alert, animated: true)
        }
    }
}

enum ShareError: LocalizedError {
    case noURL

    var errorDescription: String? { "The shared item did not contain an article URL." }
}
