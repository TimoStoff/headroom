import Testing
@testable import Headroom

@Test func releaseTagsCompareNumerically() {
    #expect(isNewer("v1.2", than: "1.1"))
    #expect(isNewer("v1.10", than: "1.9"))
    #expect(!isNewer("v1.1", than: "1.1"))
    #expect(!isNewer("v1.0", than: "1.1"))
}
