import SwiftUI
import UIKit

struct AirPrintView: UIViewControllerRepresentable {
    let fileURL: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PrintHostViewController {
        PrintHostViewController(fileURL: fileURL, onDismiss: onDismiss)
    }

    func updateUIViewController(_ uiViewController: PrintHostViewController, context: Context) {}
}

final class PrintHostViewController: UIViewController {
    private let fileURL: URL
    private var hasPresented = false
    private let onDismiss: () -> Void

    init(fileURL: URL, onDismiss: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresented else { return }
        hasPresented = true

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Booklet"
        info.outputType = .general
        info.duplex = .longEdge

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = fileURL
        let completion: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, error in
            if let error { self?.showError(error.localizedDescription) }
            else { self?.onDismiss() }
        }
        let presented: Bool
        if traitCollection.userInterfaceIdiom == .pad {
            presented = controller.present(from: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), in: view, animated: true, completionHandler: completion)
        } else {
            presented = controller.present(animated: true, completionHandler: completion)
        }
        if !presented { showError("AirPrint could not open. Close this panel and try again.") }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Couldn’t Print", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in self?.onDismiss() })
        present(alert, animated: true)
    }
}
