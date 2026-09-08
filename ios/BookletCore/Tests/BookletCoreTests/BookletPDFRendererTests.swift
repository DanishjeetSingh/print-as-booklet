import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import BookletCore

@Test func rendererCreatesTwoLandscapeSidesForFourSourcePages() throws {
    let source = makePDF(pageCount: 4)
    let result = try BookletPDFRenderer().render(sourcePDF: source)
    let document = try #require(PDFDocument(data: result))

    #expect(document.pageCount == 2)
    let size = try #require(document.page(at: 0)?.bounds(for: .mediaBox).size)
    #expect(abs(size.width - 792) < 0.1)
    #expect(abs(size.height - 612) < 0.1)
}

@Test func rendererPadsFiveSourcePagesToFourSides() throws {
    let result = try BookletPDFRenderer().render(sourcePDF: makePDF(pageCount: 5))
    let document = try #require(PDFDocument(data: result))
    #expect(document.pageCount == 4)
}

@Test func bindingGuideUsesPhysicalSheetDimensionsRegardlessOfSourceScale() {
    let oneCentimeter = CGFloat(72 / 2.54)
    let portraitLetterAfterScaling = CGRect(x: 396, y: 49.76, width: 396, height: 512.47)
    let squarePageAfterScaling = CGRect(x: 396, y: 108, width: 396, height: 396)

    for renderedPage in [portraitLetterAfterScaling, squarePageAfterScaling] {
        let guide = BookletPDFRenderer.bindingGuideGeometry(
            renderedPageRect: renderedPage,
            requestedBandWidth: oneCentimeter
        )
        #expect(abs(guide.band.width - 28.346) < 0.01)
        #expect(guide.band.minX == renderedPage.minX)
        #expect(guide.band.minY == renderedPage.minY)
        #expect(guide.band.height == renderedPage.height)
        #expect(guide.markers.count == 3)
        #expect(guide.markers.allSatisfy { abs($0.width - 3) < 0.001 })
    }
}

private func makePDF(pageCount: Int) -> Data {
    let output = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let consumer = CGDataConsumer(data: output as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    for page in 0..<pageCount {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: CGFloat(page + 1) / CGFloat(pageCount + 1), alpha: 1))
        context.fill(CGRect(x: 50, y: 50, width: 100, height: 100))
        context.endPDFPage()
    }
    context.closePDF()
    return output as Data
}
