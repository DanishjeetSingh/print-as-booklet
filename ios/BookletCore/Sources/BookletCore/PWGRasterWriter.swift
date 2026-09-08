import CoreGraphics
import Foundation

/// PWG 5102.4: network-order headers and lossless PackBits scanlines.
/// Rasterize in 128-row strips so the share extension never holds a full raster document.
struct PWGRasterWriter {
    var dpi: Int
    var sheetBack: String
    var black: Bool = false

    func write(pdfURL: URL, to output: FileHandle) throws {
        guard let pdf = CGPDFDocument(pdfURL as CFURL), pdf.numberOfPages > 0 else { throw IPPPrintError.unreadableBooklet }
        try output.write(contentsOf: Data("RaS2".utf8))
        let width = dpi * 17 / 2, height = dpi * 11
        for index in 1...pdf.numberOfPages {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { throw IPPPrintError.unreadableBooklet }
            let back = index % 2 == 0
            let flipX = back && ["flipped", "manual-tumble"].contains(sheetBack)
            let flipY = back && sheetBack == "manual-tumble"
            try output.write(contentsOf: header(width: width, height: height, count: pdf.numberOfPages, flipX: flipX, flipY: flipY))
            for top in stride(from: 0, to: height, by: 128) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let rows = min(128, height - top)
                    guard let context = CGContext(data: nil, width: width, height: rows, bitsPerComponent: 8,
                                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
                          let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { throw IPPPrintError.unreadableBooklet }
                    context.setFillColor(gray: 1, alpha: 1)
                    context.fill(CGRect(x: 0, y: 0, width: width, height: rows))
                    context.translateBy(x: 0, y: CGFloat(rows - height + top))
                    if flipX { context.translateBy(x: CGFloat(width), y: 0); context.scaleBy(x: -1, y: 1) }
                    if flipY { context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1) }
                    // Feed Letter short edge first. Rotate the landscape booklet onto portrait media.
                    // Its central fold now lies parallel to the physical short edge.
                    context.concatenate(page.getDrawingTransform(.mediaBox,
                        rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 90, preserveAspectRatio: true))
                    context.drawPDFPage(page)
                    var encoded = Data()
                    for row in 0..<rows {
                        encoded.append(0) // one occurrence of this scanline
                        let line = UnsafeBufferPointer(start: pixels + row * width, count: width)
                        encoded.append(Self.encode(line, inverted: black))
                    }
                    try output.write(contentsOf: encoded)
                }
            }
        }
    }

    static func encode(_ bytes: UnsafeBufferPointer<UInt8>, inverted: Bool = false) -> Data {
        var result = Data(), position = 0
        func value(_ i: Int) -> UInt8 { inverted ? 255 - bytes[i] : bytes[i] }
        while position < bytes.count {
            var run = 1
            while position + run < bytes.count && run < 128 && bytes[position + run] == bytes[position] { run += 1 }
            if run > 1 {
                result.append(UInt8(run - 1)); result.append(value(position)); position += run
            } else {
                let start = position; position += 1
                while position < bytes.count && position - start < 128 {
                    if position + 1 < bytes.count && bytes[position] == bytes[position + 1] { break }
                    position += 1
                }
                let count = position - start
                result.append(count == 1 ? 0 : UInt8(257 - count))
                for i in start..<position { result.append(value(i)) }
            }
        }
        return result
    }

    func header(width: Int, height: Int, count: Int, flipX: Bool, flipY: Bool) -> Data {
        var bytes = Data(repeating: 0, count: 1796)
        func number(_ offset: Int, _ value: UInt32) {
            var data = Data(); data.appendBE(value); bytes.replaceSubrange(offset..<offset + 4, with: data)
        }
        func string(_ offset: Int, _ value: String) { bytes.replaceSubrange(offset..<offset + value.utf8.count, with: value.utf8) }
        string(0, "PwgRaster")
        number(272, 1); number(276, UInt32(dpi)); number(280, UInt32(dpi))
        number(340, 1); number(352, 612); number(356, 792); number(368, 1) // portrait Letter, short-edge duplex
        number(372, UInt32(width)); number(376, UInt32(height))
        number(384, 8); number(388, 8); number(392, UInt32(width))
        number(400, black ? 3 : 18); number(420, 1) // black_8 or sgray_8
        number(452, UInt32(count)); number(456, flipX ? UInt32.max : 1); number(460, flipY ? UInt32.max : 1)
        number(472, UInt32(width)); number(476, UInt32(height))
        string(1732, "na_letter_8.5x11in")
        return bytes
    }
}
