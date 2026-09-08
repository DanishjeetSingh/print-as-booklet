import Testing
@testable import BookletCore

@Test func padsPageCountsToSignaturesOfFour() {
    #expect(BookletLayout.paddedPageCount(for: 0) == 0)
    #expect(BookletLayout.paddedPageCount(for: 1) == 4)
    #expect(BookletLayout.paddedPageCount(for: 4) == 4)
    #expect(BookletLayout.paddedPageCount(for: 9) == 12)
}

@Test func imposesEightPagesInBookletOrder() {
    #expect(BookletLayout.sides(for: 8) == [
        BookletSide(leftPage: 8, rightPage: 1),
        BookletSide(leftPage: 2, rightPage: 7),
        BookletSide(leftPage: 6, rightPage: 3),
        BookletSide(leftPage: 4, rightPage: 5),
    ])
}

@Test func representsPaddingAsBlankPages() {
    #expect(BookletLayout.sides(for: 5) == [
        BookletSide(leftPage: nil, rightPage: 1),
        BookletSide(leftPage: 2, rightPage: nil),
        BookletSide(leftPage: nil, rightPage: 3),
        BookletSide(leftPage: 4, rightPage: 5),
    ])
}
