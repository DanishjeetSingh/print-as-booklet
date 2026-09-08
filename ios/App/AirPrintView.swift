import SwiftUI
import UIKit

struct AirPrintView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> PrintHostViewController {
        PrintHostViewController(fileURL: fileURL)
    }

    func updateUIViewController(_ uiViewController: PrintHostViewController, context: Context) {}
}

final class PrintHostViewController: UIViewController {
    private let fileURL: URL
    private var hasPresented = false

    init(fileURL: URL) {
        self.fileURL = fileURL
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
        controller.present(animated: true)
    }
}
