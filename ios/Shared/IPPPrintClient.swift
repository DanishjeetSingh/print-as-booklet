import BookletCore
import Foundation

/// Resolve the Bonjour service URLs saved by AirPrint before using URLSession.
@MainActor
final class PrinterAddressResolver: NSObject, @preconcurrency NetServiceDelegate {
    private var service: NetService?
    private var continuation: CheckedContinuation<URL, Error>?
    private var secure = false

    func resolve(_ identifier: String) async throws -> URL {
        guard let address = BonjourPrinterAddress(identifier) else {
            guard let url = URL(string: identifier) else { throw IPPPrintError.unsupportedPrinterURL }
            return try PrinterEndpoint(url).uri
        }
        secure = address.secure
        let service = NetService(domain: address.domain, type: address.type, name: address.name)
        self.service = service
        service.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            service.resolve(withTimeout: 15)
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, sender.port > 0 else { finish(.failure(IPPPrintError.unsupportedPrinterURL)); return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let path = txt["rp"].flatMap { String(data: $0, encoding: .utf8) } ?? "ipp/print"
        var parts = URLComponents()
        parts.scheme = secure ? "ipps" : "ipp"; parts.host = host; parts.port = sender.port
        parts.path = path.hasPrefix("/") ? path : "/" + path
        guard let url = parts.url else { finish(.failure(IPPPrintError.unsupportedPrinterURL)); return }
        finish(.success(url))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(.failure(IPPPrintError.unsupported("Couldn’t find the saved printer. Check that it is on and your iPhone is on the same Wi-Fi network, and Local Network access is enabled for Print as Booklet in Settings, then try again or change printer.")))
    }
    private func finish(_ result: Result<URL, Error>) {
        let callback = continuation; continuation = nil
        service?.stop(); service?.delegate = nil; service = nil
        callback?.resume(with: result)
    }
}
