import Foundation

public enum IPPPrintError: LocalizedError {
    case unreadableBooklet, unsupportedPrinterURL, invalidResponse
    case httpFailure(Int), printerRejected(UInt16, String)
    case unsupported(String), uncertainSubmission(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableBooklet: "The prepared booklet could not be read."
        case .unsupportedPrinterURL: "The saved printer address could not be resolved. Choose the printer again."
        case .invalidResponse: "The printer returned an incomplete or invalid IPP response."
        case let .httpFailure(code): "The printer connection failed (HTTP \(code))."
        case let .printerRejected(code, message): "The printer rejected the request (IPP 0x\(String(code, radix: 16))). \(message)"
        case let .unsupported(message): message
        case let .uncertainSubmission(message): "The connection ended before the printer confirmed the job. Check the printer before trying again to avoid a duplicate. \(message)"
        }
    }
}

struct IPPMessage {
    let status: UInt16
    let attributes: [String: [Data]]
    func strings(_ name: String) -> [String] { (attributes[name] ?? []).compactMap { String(data: $0, encoding: .utf8) } }
    func integer(_ name: String) -> Int? {
        guard let data = attributes[name]?.first, data.count == 4 else { return nil }
        return Int(data.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
    static func parse(_ data: Data, requestID: UInt32) throws -> Self {
        let bytes = [UInt8](data)
        guard bytes.count >= 9, [1, 2].contains(bytes[0]),
              bytes[4..<8].reduce(UInt32(0), { $0 << 8 | UInt32($1) }) == requestID else { throw IPPPrintError.invalidResponse }
        let status = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        var offset = 8, group: UInt8 = 0
        var name = "", result: [String: [Data]] = [:]
        func readLength() throws -> Int {
            guard offset + 2 <= bytes.count else { throw IPPPrintError.invalidResponse }
            defer { offset += 2 }
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }
        while offset < bytes.count {
            let tag = bytes[offset]; offset += 1
            if tag == 3 {
                let message = Self(status: status, attributes: result)
                // Only 0x00xx is successful. Redirection (0x03xx) is not acceptance.
                guard status < 0x0100 else { throw IPPPrintError.printerRejected(status, message.strings("status-message").first ?? "") }
                return message
            }
            if tag < 0x10 { group = tag; name = ""; continue }
            let length = try readLength()
            guard offset + length <= bytes.count else { throw IPPPrintError.invalidResponse }
            if length > 0 { name = String(decoding: bytes[offset..<offset + length], as: UTF8.self) }
            offset += length
            let valueLength = try readLength()
            guard !name.isEmpty, offset + valueLength <= bytes.count else { throw IPPPrintError.invalidResponse }
            // Ignore unsupported-attributes groups when interpreting capabilities.
            if group != 5 { result[name, default: []].append(Data(bytes[offset..<offset + valueLength])) }
            offset += valueLength
        }
        throw IPPPrintError.invalidResponse
    }
}

struct IPPRequest {
    let id: UInt32
    var data: Data
    init(operation: UInt16, uri: URL, id: UInt32 = UInt32.random(in: 1...UInt32(Int32.max))) {
        self.id = id
        data = Data([1, 1]) // IPP/1.1 works with IPP Everywhere printers as well.
        data.appendBE(operation); data.appendBE(id); data.append(1)
        attribute(0x47, "attributes-charset", "utf-8")
        attribute(0x48, "attributes-natural-language", "en")
        attribute(0x45, "printer-uri", uri.absoluteString)
    }
    mutating func attribute(_ tag: UInt8, _ name: String, _ value: String) { attribute(tag, name, Data(value.utf8)) }
    mutating func attribute(_ tag: UInt8, _ name: String, _ value: Data) {
        data.append(tag); data.appendBE(UInt16(name.utf8.count)); data.append(contentsOf: name.utf8)
        data.appendBE(UInt16(value.count)); data.append(value)
    }
    mutating func integer(_ name: String, _ value: UInt32, tag: UInt8 = 0x21) {
        var bytes = Data(); bytes.appendBE(value); attribute(tag, name, bytes)
    }
}

public struct PrinterEndpoint: Sendable {
    public let uri: URL
    public let httpURL: URL
    public init(_ url: URL) throws {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty, !host.contains("._tcp"),
              parts.user == nil, parts.password == nil else { throw IPPPrintError.unsupportedPrinterURL }
        switch parts.scheme?.lowercased() {
        case "ipp", "ipps": if parts.port == nil { parts.port = 631 }
        case "http": parts.scheme = "ipp"; if parts.port == nil { parts.port = 80 }
        case "https": parts.scheme = "ipps"; if parts.port == nil { parts.port = 443 }
        default: throw IPPPrintError.unsupportedPrinterURL
        }
        parts.fragment = nil
        guard let uri = parts.url else { throw IPPPrintError.unsupportedPrinterURL }
        self.uri = uri
        parts.scheme = parts.scheme == "ipps" ? "https" : "http"
        guard let httpURL = parts.url else { throw IPPPrintError.unsupportedPrinterURL }
        self.httpURL = httpURL
    }
}

extension Data {
    mutating func appendBE(_ value: UInt16) { append(UInt8(value >> 8)); append(UInt8(value & 255)) }
    mutating func appendBE(_ value: UInt32) { for shift in [24, 16, 8, 0] { append(UInt8((value >> shift) & 255)) } }
}

/// UIPrintInfo.printerID can be a bare DNS-SD service name, not an IPP URL.
/// DNS-SD escapes service-name bytes as backslash + three decimal digits.
public struct BonjourPrinterAddress: Sendable {
    public let name: String
    public let domain: String
    public let type: String
    public var secure: Bool { type == "_ipps._tcp." }

    public init?(_ identifier: String) {
        let host: String
        if identifier.contains("://") {
            guard let url = URL(string: identifier), let value = url.host else { return nil }
            host = value.removingPercentEncoding ?? value
        } else { host = identifier.removingPercentEncoding ?? identifier }
        guard let marker = host.range(of: "._ipps._tcp.", options: .caseInsensitive)
                ?? host.range(of: "._ipp._tcp.", options: .caseInsensitive) else { return nil }
        let encodedName = Array(host[..<marker.lowerBound].utf8)
        var decoded: [UInt8] = [], index = 0
        while index < encodedName.count {
            if encodedName[index] == 92 {
                if index + 3 < encodedName.count,
                   encodedName[(index + 1)...(index + 3)].allSatisfy({ (48...57).contains($0) }) {
                    let value = encodedName[(index + 1)...(index + 3)].reduce(0) { $0 * 10 + Int($1 - 48) }
                    guard value > 0 && value <= 255 else { return nil }
                    decoded.append(UInt8(value)); index += 4; continue
                }
                guard index + 1 < encodedName.count else { return nil }
                decoded.append(encodedName[index + 1]); index += 2; continue
            }
            decoded.append(encodedName[index]); index += 1
        }
        guard let name = String(bytes: decoded, encoding: .utf8), !name.isEmpty else { return nil }
        let domain = String(host[marker.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty, !domain.contains("/"), !domain.contains(" ") else { return nil }
        self.name = name
        self.domain = domain + "."
        self.type = host[marker].lowercased().contains("_ipps") ? "_ipps._tcp." : "_ipp._tcp."
    }
}
