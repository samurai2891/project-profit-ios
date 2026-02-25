import XCTest
@testable import ProjectProfit

@MainActor
final class ClassificationDictionaryLoaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ClassificationDictionaryLoader.clearCache()
    }

    override func tearDown() {
        ClassificationDictionaryLoader.clearCache()
        super.tearDown()
    }

    // MARK: - JSON Loading

    func testLoad_returnsNonEmptyRules() {
        let rules = ClassificationDictionaryLoader.load()
        XCTAssertFalse(rules.isEmpty, "Should load classification rules from JSON")
    }

    func testLoad_matchesInlineFallbackCount() {
        let jsonRules = ClassificationDictionaryLoader.load()
        let inlineRules = ClassificationDictionaryLoader.inlineFallback
        XCTAssertEqual(jsonRules.count, inlineRules.count, "JSON rules count should match inline fallback count")
    }

    func testLoad_matchesInlineFallbackContent() {
        let jsonRules = ClassificationDictionaryLoader.load()
        let inlineRules = ClassificationDictionaryLoader.inlineFallback

        for (index, inline) in inlineRules.enumerated() {
            guard index < jsonRules.count else {
                XCTFail("JSON rules has fewer entries than inline fallback")
                return
            }
            let json = jsonRules[index]
            XCTAssertEqual(json.keyword, inline.keyword, "Keyword mismatch at index \(index)")
            XCTAssertEqual(json.taxLine, inline.taxLine, "TaxLine mismatch at index \(index) for keyword '\(inline.keyword)'")
        }
    }

    func testLoad_cachesResult() {
        let first = ClassificationDictionaryLoader.load()
        let second = ClassificationDictionaryLoader.load()
        XCTAssertEqual(first.count, second.count, "Cached result should be identical")
    }
}
