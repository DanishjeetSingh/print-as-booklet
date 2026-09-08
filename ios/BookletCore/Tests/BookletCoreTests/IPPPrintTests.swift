import CoreGraphics
import Foundation
import Testing
@testable import BookletCore

struct IPPPrintTests {
    @Test func restoresTheBareBonjourIdentifierSavedByAirPrint() throws {
        let saved = try #require(BonjourPrinterAddress(#"Brother\032HL-L2420DW._ipps._tcp.local."#))
        #expect(saved.name == "Brother HL-L2420DW")
        #expect(saved.domain == "local.")
        #expect(saved.secure)
        let url = try #require(BonjourPrinterAddress("ipp://Brother%20HL-L2420DW._ipp._tcp.local./"))
        #expect(url.name == saved.name); #expect(!url.secure)
        #expect(BonjourPrinterAddress("ipps://printer.local:443/ipp/print") == nil)
        #expect(BonjourPrinterAddress(#"Bad\999Name._ipps._tcp.local."#) == nil)
    }

    @Test func ippUsesPort631AndPreservesExplicitPorts() throws {
        #expect(try PrinterEndpoint(URL(string: "ipp://printer.local/ipp/print")!).httpURL.absoluteString == "http://printer.local:631/ipp/print")
        #expect(try PrinterEndpoint(URL(string: "ipps://printer.local/ipp/print")!).httpURL.absoluteString == "https://printer.local:631/ipp/print")
        #expect(try PrinterEndpoint(URL(string: "ipps://printer.local:443/ipp/print")!).httpURL.port == 443)
        #expect(try PrinterEndpoint(URL(string: "https://printer.local/ipp/print")!).uri.port == 443)
        #expect(throws: (any Error).self) { try PrinterEndpoint(URL(string: "dnssd://Printer._ipps._tcp.local/")!) }
    }

    @Test func parsesMultivalueAttributesAndJobID() throws {
        var response = IPPRequest(operation: 0, uri: URL(string: "ipp://printer.local/ipp/print")!, id: 42)
        response.data.append(4)
        response.attribute(0x49, "document-format-supported", "image/urf")
        response.attribute(0x49, "", "image/pwg-raster")
        response.integer("job-id", 123)
        response.data.append(3)
        let result = try IPPMessage.parse(response.data, requestID: 42)
        #expect(result.strings("document-format-supported") == ["image/urf", "image/pwg-raster"])
        #expect(result.integer("job-id") == 123)
    }

    @Test func rejectsTruncationMismatchedIDsAndRedirectStatuses() throws {
        let valid = Data([1, 1, 0, 0, 0, 0, 0, 42, 3])
        #expect(throws: (any Error).self) { try IPPMessage.parse(valid, requestID: 43) }
        #expect(throws: (any Error).self) { try IPPMessage.parse(valid.dropLast(), requestID: 42) }
        #expect(throws: (any Error).self) { try IPPMessage.parse(Data([1, 1, 3, 0, 0, 0, 0, 42, 3]), requestID: 42) }
        for length in 0..<valid.count {
            #expect(throws: (any Error).self) { try IPPMessage.parse(valid.prefix(length), requestID: 42) }
        }
    }

    @Test func brotherRasterCapabilityDoesNotSelectPDF() throws {
        let brother = IPPMessage(status: 0, attributes: ["document-format-supported": [Data("application/octet-stream".utf8), Data("image/urf".utf8), Data("image/pwg-raster".utf8)]])
        #expect(try IPPPrintClient.documentFormat(brother) == "image/pwg-raster")
        let pdf = IPPMessage(status: 0, attributes: ["document-format-supported": [Data("application/pdf".utf8), Data("image/pwg-raster".utf8)]])
        #expect(try IPPPrintClient.documentFormat(pdf) == "application/pdf")
        #expect(throws: (any Error).self) { try IPPPrintClient.documentFormat(IPPMessage(status: 0, attributes: [:])) }
    }

    @Test func rasterUsesAnAdvertisedResolutionAndColorSpace() throws {
        func resolution(_ dpi: UInt32) -> Data { var data = Data(); data.appendBE(dpi); data.appendBE(dpi); data.append(3); return data }
        let caps = IPPMessage(status: 0, attributes: [
            "pwg-raster-document-type-supported": [Data("sgray_8".utf8)],
            "pwg-raster-document-resolution-supported": [resolution(600), resolution(300)],
            "pwg-raster-document-sheet-back": [Data("rotated".utf8)],
        ])
        let options = try IPPPrintClient.rasterOptions(caps)
        #expect(options.dpi == 300); #expect(options.back == "rotated"); #expect(!options.black)
        #expect(throws: (any Error).self) { try IPPPrintClient.rasterOptions(IPPMessage(status: 0, attributes: [:])) }
    }

    @Test func compressionRoundTripsRunBoundariesAndLiteralBytes() throws {
        let lines: [[UInt8]] = [
            [0], [0, 255], Array(repeating: 255, count: 2550),
            (0..<2550).map { UInt8($0 % 256) },
            Array(repeating: 17, count: 129) + [1, 2, 3] + Array(repeating: 255, count: 257),
        ]
        for line in lines {
            for inverted in [true, false] {
                let encoded = line.withUnsafeBufferPointer { PWGRasterWriter.encode($0, inverted: inverted) }
                var offset = 0
                let decoded = try decodeLine([UInt8](encoded), offset: &offset, width: line.count)
                #expect(decoded == line.map { inverted ? 255 - $0 : $0 })
                #expect(offset == encoded.count)
            }
        }
    }

    @Test func rasterStripsMatchWholePageRenderingAndDuplexTransforms() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.pdf")
        var box = CGRect(x: 0, y: 0, width: 792, height: 612)
        let pdfContext = try #require(CGContext(source as CFURL, mediaBox: &box, nil))
        for _ in 0..<2 {
            pdfContext.beginPDFPage(nil)
            pdfContext.setFillColor(gray: 0, alpha: 1)
            pdfContext.fill(CGRect(x: 25, y: 35, width: 125, height: 95))
            pdfContext.setFillColor(gray: 0.5, alpha: 1)
            pdfContext.fill(CGRect(x: 480, y: 410, width: 225, height: 150))
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
        let pdf = try #require(CGPDFDocument(source as CFURL))
        let width = 153, height = 198 // 18 dpi keeps the regression fixture tiny; crosses the 128-row strip boundary.
        for back in ["normal", "rotated", "flipped", "manual-tumble"] {
            let target = folder.appendingPathComponent("\(back).pwg")
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let output = try FileHandle(forWritingTo: target)
            try PWGRasterWriter(dpi: 18, sheetBack: back).write(pdfURL: source, to: output)
            try output.close()
            let bytes = [UInt8](try Data(contentsOf: target))
            #expect(String(decoding: bytes.prefix(4), as: UTF8.self) == "RaS2")
            var offset = 4
            for index in 1...2 {
                let header = Array(bytes[offset..<offset + 1796]); offset += 1796
                func number(_ start: Int) -> UInt32 { header[start..<start + 4].reduce(0) { $0 << 8 | UInt32($1) } }
                #expect(number(272) == 1); #expect(number(368) == 1)
                #expect(number(352) == 612); #expect(number(356) == 792)
                #expect(number(372) == UInt32(width)); #expect(number(376) == UInt32(height)); #expect(number(452) == 2)
                let flipX = index == 2 && ["flipped", "manual-tumble"].contains(back)
                let flipY = index == 2 && back == "manual-tumble"
                #expect(number(456) == (flipX ? UInt32.max : 1))
                #expect(number(460) == (flipY ? UInt32.max : 1))
                var actual: [UInt8] = []
                for _ in 0..<height {
                    #expect(bytes[offset] == 0); offset += 1
                    actual += try decodeLine(bytes, offset: &offset, width: width)
                }
                let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
                context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                let page = try #require(pdf.page(at: index))
                context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 90, preserveAspectRatio: true))
                context.drawPDFPage(page)
                let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
                for y in 0..<height {
                    for x in 0..<width {
                        let expected = pixels[(flipY ? height - 1 - y : y) * width + (flipX ? width - 1 - x : x)]
                        #expect(abs(Int(actual[y * width + x]) - Int(expected)) <= 1)
                    }
                }
            }
            #expect(offset == bytes.count)
        }
    }

    private func decodeLine(_ bytes: [UInt8], offset: inout Int, width: Int) throws -> [UInt8] {
        var pixels: [UInt8] = []
        while pixels.count < width {
            guard offset < bytes.count else { throw IPPPrintError.invalidResponse }
            let token = Int(bytes[offset]); offset += 1
            if token < 128 {
                guard offset < bytes.count else { throw IPPPrintError.invalidResponse }
                pixels += Array(repeating: bytes[offset], count: token + 1); offset += 1
            } else {
                let count = 257 - token
                guard offset + count <= bytes.count else { throw IPPPrintError.invalidResponse }
                pixels += bytes[offset..<offset + count]; offset += count
            }
        }
        guard pixels.count == width else { throw IPPPrintError.invalidResponse }
        return pixels
    }
}
