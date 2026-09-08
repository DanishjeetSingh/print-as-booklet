import Foundation

public struct BookletSide: Sendable, Equatable {
    /// One-based source page numbers. `nil` represents an inserted blank page.
    public let leftPage: Int?
    public let rightPage: Int?

    public init(leftPage: Int?, rightPage: Int?) {
        self.leftPage = leftPage
        self.rightPage = rightPage
    }
}

public enum BookletLayout {
    public static func paddedPageCount(for sourcePageCount: Int) -> Int {
        guard sourcePageCount > 0 else { return 0 }
        return ((sourcePageCount + 3) / 4) * 4
    }

    /// Returns sheet sides in printer order: front, back, front, back.
    public static func sides(for sourcePageCount: Int) -> [BookletSide] {
        let total = paddedPageCount(for: sourcePageCount)
        guard total > 0 else { return [] }

        func existingPage(_ number: Int) -> Int? {
            number <= sourcePageCount ? number : nil
        }

        var result: [BookletSide] = []
        for sheet in 0..<(total / 4) {
            result.append(BookletSide(
                leftPage: existingPage(total - 2 * sheet),
                rightPage: existingPage(1 + 2 * sheet)
            ))
            result.append(BookletSide(
                leftPage: existingPage(2 + 2 * sheet),
                rightPage: existingPage(total - 1 - 2 * sheet)
            ))
        }
        return result
    }
}
