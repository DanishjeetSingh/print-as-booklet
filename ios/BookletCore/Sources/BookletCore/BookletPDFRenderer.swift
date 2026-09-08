import CoreGraphics
import CoreText
import Foundation
import PDFKit

public enum BookletPDFRendererError: LocalizedError {
    case unreadablePDF
    case emptyPDF
    case outputCreationFailed

    public var errorDescription: String? {
        switch self {
        case .unreadablePDF: "The downloaded data is not a readable PDF."
        case .emptyPDF: "The downloaded PDF contains no pages."
        case .outputCreationFailed: "The booklet PDF could not be created."
        }
    }
}

public struct BookletRenderOptions: Sendable {
    public var sheetSize: CGSize
    public var gutter: CGFloat
    public var pageNumberFontSizeRange: ClosedRange<CGFloat>
    public var bindingBandWidth: CGFloat

    public init(
        sheetSize: CGSize = CGSize(width: 792, height: 612), // US Letter landscape
        gutter: CGFloat = 0,
        pageNumberFontSizeRange: ClosedRange<CGFloat> = 12...14,
        bindingBandWidth: CGFloat = 72 / 2.54 // 1 cm
    ) {
        self.sheetSize = sheetSize
        self.gutter = gutter
        self.pageNumberFontSizeRange = pageNumberFontSizeRange
        self.bindingBandWidth = bindingBandWidth
    }
}

public struct BookletPDFRenderer: Sendable {
    public var options: BookletRenderOptions

    public init(options: BookletRenderOptions = .init()) {
        self.options = options
    }

    public func render(sourcePDF: Data) throws -> Data {
        guard let source = PDFDocument(data: sourcePDF) else {
            throw BookletPDFRendererError.unreadablePDF
        }
        guard source.pageCount > 0 else {
            throw BookletPDFRendererError.emptyPDF
        }

        let output = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: output as CFMutableData),
            var mediaBox = Optional(CGRect(origin: .zero, size: options.sheetSize)),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw BookletPDFRendererError.outputCreationFailed
        }

        for side in BookletLayout.sides(for: source.pageCount) {
            context.beginPDFPage(nil)
            draw(pageNumber: side.leftPage, from: source, inLeftHalf: true, context: context)
            draw(pageNumber: side.rightPage, from: source, inLeftHalf: false, context: context)
            context.endPDFPage()
        }
        context.closePDF()
        guard !output.isEmpty else {
            throw BookletPDFRendererError.outputCreationFailed
        }
        return output as Data
    }

    private func draw(
        pageNumber: Int?,
        from source: PDFDocument,
        inLeftHalf: Bool,
        context: CGContext
    ) {
        guard
            let pageNumber,
            let page = source.page(at: pageNumber - 1)
        else { return }

        let halfWidth = (options.sheetSize.width - options.gutter) / 2
        let target = CGRect(
            x: inLeftHalf ? 0 : halfWidth + options.gutter,
            y: 0,
            width: halfWidth,
            height: options.sheetSize.height
        )
        let sourceBounds = page.bounds(for: .mediaBox)
        guard sourceBounds.width > 0, sourceBounds.height > 0 else { return }

        let scale = min(target.width / sourceBounds.width, target.height / sourceBounds.height)
        let renderedSize = CGSize(width: sourceBounds.width * scale, height: sourceBounds.height * scale)
        let origin = CGPoint(
            x: target.midX - renderedSize.width / 2,
            y: target.midY - renderedSize.height / 2
        )

        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
        page.draw(with: .mediaBox, to: context)
        drawPageNumber(pageNumber, pageSize: sourceBounds.size, context: context)
        context.restoreGState()

        if pageNumber == 1 {
            drawBindingGuide(
                renderedPageRect: CGRect(origin: origin, size: renderedSize),
                context: context
            )
        }
    }

    private func drawPageNumber(_ number: Int, pageSize: CGSize, context: CGContext) {
        let desiredSize = min(pageSize.width, pageSize.height) / 44
        let fontSize = min(max(desiredSize, options.pageNumberFontSizeRange.lowerBound), options.pageNumberFontSizeRange.upperBound)
        let font = CTFontCreateWithName("Times-Roman" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.28, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: attributes))
        let textBounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        let baseline = max(20, pageSize.height * 0.03)
        let background = CGRect(
            x: (pageSize.width - textBounds.width) / 2 - 5,
            y: baseline - 2.5,
            width: textBounds.width + 10,
            height: fontSize + 5
        )

        context.setFillColor(CGColor(gray: 1, alpha: 0.88))
        context.addPath(CGPath(roundedRect: background, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
        context.textPosition = CGPoint(x: (pageSize.width - textBounds.width) / 2, y: baseline)
        CTLineDraw(line, context)
    }

    private func drawBindingGuide(renderedPageRect: CGRect, context: CGContext) {
        let geometry = Self.bindingGuideGeometry(
            renderedPageRect: renderedPageRect,
            requestedBandWidth: options.bindingBandWidth
        )
        context.setFillColor(CGColor(gray: 0.91, alpha: 1))
        context.fill(geometry.band)

        context.setFillColor(CGColor(gray: 0.38, alpha: 1))
        for marker in geometry.markers {
            context.addPath(CGPath(
                roundedRect: marker,
                cornerWidth: marker.width / 2,
                cornerHeight: marker.width / 2,
                transform: nil
            ))
            context.fillPath()
        }
    }

    struct BindingGuideGeometry: Equatable {
        let band: CGRect
        let markers: [CGRect]
    }

    static func bindingGuideGeometry(
        renderedPageRect: CGRect,
        requestedBandWidth: CGFloat
    ) -> BindingGuideGeometry {
        let width = min(requestedBandWidth, renderedPageRect.width)
        let band = CGRect(
            x: renderedPageRect.minX,
            y: renderedPageRect.minY,
            width: width,
            height: renderedPageRect.height
        )
        let markerWidth = min(CGFloat(3), width)
        let markerHeight = width * 0.64
        let markerX = band.midX - markerWidth / 2
        let markers = [CGFloat(0.15), 0.5, 0.85].map { fraction in
            CGRect(
                x: markerX,
                y: band.minY + band.height * fraction - markerHeight / 2,
                width: markerWidth,
                height: markerHeight
            )
        }
        return BindingGuideGeometry(band: band, markers: markers)
    }
}
