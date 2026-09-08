import Foundation

public struct IPPPrintReceipt: Sendable {
    public let jobID: Int?
    public let format: String
}

public struct IPPPrintClient: Sendable {
    public init() {}

    public func printBooklet(at fileURL: URL, to printerURL: URL,
                             progress: @Sendable (String) async -> Void = { _ in }) async throws -> IPPPrintReceipt {
        let endpoint = try PrinterEndpoint(printerURL)
        let delegate = LocalPrinterTrustDelegate(allowedHost: endpoint.httpURL.host ?? "")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        await progress("Checking printer…")
        var query = IPPRequest(operation: 0x000b, uri: endpoint.uri)
        for (index, name) in ["document-format-supported", "sides-supported", "media-supported", "pwg-raster-document-type-supported",
                              "pwg-raster-document-resolution-supported", "pwg-raster-document-sheet-back"].enumerated() {
            query.attribute(0x44, index == 0 ? "requested-attributes" : "", name)
        }
        query.data.append(3)
        let capabilities = try await send(query, endpoint: endpoint, session: session)
        let format = try Self.documentFormat(capabilities)
        let sides = format == "image/pwg-raster" ? "two-sided-short-edge" : "two-sided-long-edge"
        guard capabilities.strings("sides-supported").contains(sides) else {
            throw IPPPrintError.unsupported("This printer does not report automatic duplex support. Use Standard Print to choose print settings.")
        }
        let media = capabilities.strings("media-supported")
        guard media.contains("na_letter_8.5x11in") else {
            throw IPPPrintError.unsupported("This printer does not report Letter paper support. Use Standard Print to choose the paper size.")
        }

        var job = IPPRequest(operation: 0x0002, uri: endpoint.uri)
        job.attribute(0x42, "requesting-user-name", "Booklet")
        job.attribute(0x42, "job-name", "Booklet")
        job.attribute(0x49, "document-format", format)
        job.attribute(0x22, "ipp-attribute-fidelity", Data([1]))
        job.data.append(2)
        job.integer("copies", 1)
        job.attribute(0x44, "sides", sides)
        job.attribute(0x44, "media", "na_letter_8.5x11in")
        job.data.append(3)

        let spool = FileManager.default.temporaryDirectory.appendingPathComponent("booklet-job-\(UUID().uuidString).ipp")
        defer { try? FileManager.default.removeItem(at: spool) }
        await progress("Preparing for printer…")
        let raster = format == "image/pwg-raster" ? try Self.rasterOptions(capabilities) : nil
        let prefix = job.data
        // Off the main actor; the extension remains responsive while pages are rendered.
        let rendering = Task.detached(priority: .userInitiated) {
            guard FileManager.default.createFile(atPath: spool.path, contents: nil) else { throw IPPPrintError.unreadableBooklet }
            let output = try FileHandle(forWritingTo: spool)
            defer { try? output.close() }
            try output.write(contentsOf: prefix)
            if let raster {
                try PWGRasterWriter(dpi: raster.dpi, sheetBack: raster.back, black: raster.black).write(pdfURL: fileURL, to: output)
            } else {
                let input = try FileHandle(forReadingFrom: fileURL)
                defer { try? input.close() }
                guard let signature = try input.read(upToCount: 5), signature == Data("%PDF-".utf8) else { throw IPPPrintError.unreadableBooklet }
                try output.write(contentsOf: signature)
                while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: chunk)
                }
            }
        }
        try await withTaskCancellationHandler { try await rendering.value } onCancel: { rendering.cancel() }
        try Task.checkCancellation()
        await progress("Sending to printer…")
        var request = URLRequest(url: endpoint.httpURL)
        request.httpMethod = "POST"
        request.setValue("application/ipp", forHTTPHeaderField: "Content-Type")
        request.setValue("application/ipp", forHTTPHeaderField: "Accept")
        let size = try FileManager.default.attributesOfItem(atPath: spool.path)[.size] as? NSNumber
        request.setValue(size?.stringValue, forHTTPHeaderField: "Content-Length")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: spool)
        } catch {
            // Never automatically resubmit a potentially accepted job.
            throw IPPPrintError.uncertainSubmission(error.localizedDescription)
        }
        let receipt: IPPMessage
        do { receipt = try Self.response(data, response, id: job.id) }
        catch let error as IPPPrintError {
            if case .invalidResponse = error { throw IPPPrintError.uncertainSubmission(error.localizedDescription) }
            throw error
        }
        return IPPPrintReceipt(jobID: receipt.integer("job-id"), format: format)
    }

    static func documentFormat(_ capabilities: IPPMessage) throws -> String {
        let formats = capabilities.strings("document-format-supported")
        if formats.contains("application/pdf") { return "application/pdf" }
        if formats.contains("image/pwg-raster") { return "image/pwg-raster" }
        throw IPPPrintError.unsupported("This printer needs an AirPrint conversion that Quick Print does not support. Use Standard Print.")
    }

    static func rasterOptions(_ capabilities: IPPMessage) throws -> (dpi: Int, back: String, black: Bool) {
        let types = capabilities.strings("pwg-raster-document-type-supported")
        guard types.contains("sgray_8") || types.contains("black_8") else {
            throw IPPPrintError.unsupported("This printer does not support Quick Print’s grayscale format. Use Standard Print.")
        }
        let resolutions = (capabilities.attributes["pwg-raster-document-resolution-supported"] ?? []).compactMap { data -> Int? in
            let b = [UInt8](data)
            guard b.count == 9, b[8] == 3 else { return nil } // dots per inch
            let x = b[0..<4].reduce(0) { $0 << 8 | Int($1) }
            let y = b[4..<8].reduce(0) { $0 << 8 | Int($1) }
            return x == y && (150...600).contains(x) ? x : nil
        }
        guard let dpi = resolutions.min(by: { abs($0 - 300) < abs($1 - 300) }) else {
            throw IPPPrintError.unsupported("This printer does not report a supported raster resolution. Use Standard Print.")
        }
        let back = capabilities.strings("pwg-raster-document-sheet-back").first ?? "normal"
        guard ["normal", "rotated", "flipped", "manual-tumble"].contains(back) else {
            throw IPPPrintError.unsupported("This printer uses an unsupported duplex layout. Use Standard Print.")
        }
        return (dpi, back, !types.contains("sgray_8"))
    }

    private func send(_ message: IPPRequest, endpoint: PrinterEndpoint, session: URLSession) async throws -> IPPMessage {
        var request = URLRequest(url: endpoint.httpURL)
        request.httpMethod = "POST"; request.httpBody = message.data
        request.setValue("application/ipp", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        return try Self.response(data, response, id: message.id)
    }

    private static func response(_ data: Data, _ response: URLResponse, id: UInt32) throws -> IPPMessage {
        guard let http = response as? HTTPURLResponse else { throw IPPPrintError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw IPPPrintError.httpFailure(http.statusCode) }
        return try IPPMessage.parse(data, requestID: id)
    }
}

private final class LocalPrinterTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let allowedHost: String
    init(allowedHost: String) { self.allowedHost = allowedHost }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(allowedHost) == .orderedSame,
              Self.isLocal(allowedHost), let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    // Do not redirect a document to a different service or turn a POST into a GET.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    static func isLocal(_ host: String) -> Bool {
        let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if value.hasSuffix(".local") { return true }
        let octets = value.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
            return octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 169 && octets[1] == 254)
        }
        return value.contains(":") && (value.hasPrefix("fe80:") || value.hasPrefix("fc") || value.hasPrefix("fd"))
    }
}
