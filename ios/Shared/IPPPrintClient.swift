import Foundation

enum IPPPrintError: LocalizedError {
    case unreadableBooklet
    case unsupportedPrinterURL
    case invalidResponse
    case httpFailure(Int)
    case printerRejected(UInt16)

    var errorDescription: String? {
        switch self {
        case .unreadableBooklet:
            "The prepared booklet could not be read."
        case .unsupportedPrinterURL:
            "The selected printer did not provide a usable IPP address."
        case .invalidResponse:
            "The printer returned an invalid response."
        case let .httpFailure(status):
            "The printer connection failed with HTTP status \(status)."
        case let .printerRejected(status):
            "The printer rejected the job (IPP status 0x\(String(status, radix: 16)))."
        }
    }
}

struct IPPPrintClient {
    func printBooklet(at fileURL: URL, to printerURL: URL) async throws {
        guard let pdf = try? Data(contentsOf: fileURL), !pdf.isEmpty else {
            throw IPPPrintError.unreadableBooklet
        }

        let endpoint = try httpEndpoint(for: printerURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/ipp", forHTTPHeaderField: "Content-Type")
        request.setValue("application/ipp", forHTTPHeaderField: "Accept")
        request.httpBody = makePrintJob(printerURI: printerURL.absoluteString, pdf: pdf)

        let delegate = LocalPrinterTrustDelegate(allowedHost: endpoint.host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IPPPrintError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IPPPrintError.httpFailure(http.statusCode)
        }
        guard responseData.count >= 8 else {
            throw IPPPrintError.invalidResponse
        }

        let status = UInt16(responseData[responseData.startIndex + 2]) << 8
            | UInt16(responseData[responseData.startIndex + 3])
        guard status < 0x0400 else {
            throw IPPPrintError.printerRejected(status)
        }
    }

    private func httpEndpoint(for printerURL: URL) throws -> URL {
        guard var components = URLComponents(url: printerURL, resolvingAgainstBaseURL: false) else {
            throw IPPPrintError.unsupportedPrinterURL
        }
        switch components.scheme?.lowercased() {
        case "ipp":
            components.scheme = "http"
        case "ipps":
            components.scheme = "https"
        case "http", "https":
            break
        default:
            throw IPPPrintError.unsupportedPrinterURL
        }
        guard let endpoint = components.url else {
            throw IPPPrintError.unsupportedPrinterURL
        }
        return endpoint
    }

    private func makePrintJob(printerURI: String, pdf: Data) -> Data {
        var request = Data()
        request.append(contentsOf: [0x02, 0x00]) // IPP/2.0
        request.appendBigEndian(UInt16(0x0002)) // Print-Job
        request.appendBigEndian(UInt32.random(in: 1...UInt32.max))

        request.append(0x01) // operation-attributes-tag
        request.appendAttribute(tag: 0x47, name: "attributes-charset", value: Data("utf-8".utf8))
        request.appendAttribute(tag: 0x48, name: "attributes-natural-language", value: Data("en".utf8))
        request.appendAttribute(tag: 0x45, name: "printer-uri", value: Data(printerURI.utf8))
        request.appendAttribute(tag: 0x42, name: "requesting-user-name", value: Data("Print as Booklet".utf8))
        request.appendAttribute(tag: 0x42, name: "job-name", value: Data("Booklet".utf8))
        request.appendAttribute(tag: 0x49, name: "document-format", value: Data("application/pdf".utf8))

        request.append(0x02) // job-attributes-tag
        var copies = Data()
        copies.appendBigEndian(UInt32(1))
        request.appendAttribute(tag: 0x21, name: "copies", value: copies)
        request.appendAttribute(tag: 0x44, name: "sides", value: Data("two-sided-long-edge".utf8))
        request.appendAttribute(tag: 0x44, name: "media", value: Data("na_letter_8.5x11in".utf8))

        request.append(0x03) // end-of-attributes-tag
        request.append(pdf)
        return request
    }
}

private final class LocalPrinterTrustDelegate: NSObject, URLSessionDelegate {
    private let allowedHost: String?

    init(allowedHost: String?) {
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            challenge.protectionSpace.host.caseInsensitiveCompare(allowedHost ?? "") == .orderedSame,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendAttribute(tag: UInt8, name: String, value: Data) {
        let nameData = Data(name.utf8)
        append(tag)
        appendBigEndian(UInt16(nameData.count))
        append(nameData)
        appendBigEndian(UInt16(value.count))
        append(value)
    }
}
