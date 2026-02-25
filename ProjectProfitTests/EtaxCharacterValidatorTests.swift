import XCTest
@testable import ProjectProfit

final class EtaxCharacterValidatorTests: XCTestCase {

    // MARK: - ASCII

    func testASCIIPrintableIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("Hello World 123"))
        XCTAssertTrue(EtaxCharacterValidator.isValid("abc@def.com"))
        XCTAssertTrue(EtaxCharacterValidator.isValid("$100 + (200)"))
    }

    func testASCIIControlCharIsInvalid() {
        let tabString = "Hello\tWorld"
        XCTAssertFalse(EtaxCharacterValidator.isValid(tabString))
    }

    // MARK: - Japanese Characters

    func testHiraganaIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("あいうえお"))
    }

    func testKatakanaIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("アイウエオ"))
    }

    func testKanjiIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("確定申告"))
    }

    func testFullWidthAlphanumericIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("ＡＢＣ１２３"))
    }

    func testFullWidthSpaceIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("　")) // U+3000
    }

    func testCJKPunctuationIsValid() {
        XCTAssertTrue(EtaxCharacterValidator.isValid("、。「」"))
    }

    // MARK: - Invalid Characters

    func testEmojiIsInvalid() {
        XCTAssertFalse(EtaxCharacterValidator.isValid("テスト🎉"))
    }

    // MARK: - findInvalidCharacters

    func testFindInvalidCharactersEmpty() {
        let result = EtaxCharacterValidator.findInvalidCharacters(in: "確定申告ABC")
        XCTAssertTrue(result.isEmpty)
    }

    func testFindInvalidCharactersDetectsEmoji() {
        let result = EtaxCharacterValidator.findInvalidCharacters(in: "テスト🎉OK")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, "🎉")
    }

    // MARK: - Sanitize

    func testSanitizeReplacesInvalidWithFullWidthSpace() {
        let sanitized = EtaxCharacterValidator.sanitize("テスト🎉OK")
        XCTAssertTrue(EtaxCharacterValidator.isValid(sanitized))
        XCTAssertTrue(sanitized.contains("テスト"))
        XCTAssertTrue(sanitized.contains("OK"))
        // Emoji replaced with fullwidth space U+3000
        XCTAssertTrue(sanitized.contains("\u{3000}"))
    }

    func testSanitizePreservesValidText() {
        let original = "確定申告ABC123"
        let sanitized = EtaxCharacterValidator.sanitize(original)
        XCTAssertEqual(sanitized, original)
    }

    // MARK: - Form Validation

    func testValidateFormEmptyFieldsReturnsNoDataError() {
        let form = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: [],
            generatedAt: Date()
        )
        let errors = EtaxCharacterValidator.validateForm(form)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].description.contains("データがありません"))
    }

    func testValidateFormWithFieldsReturnsNoErrors() {
        let form = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: [
                EtaxField(
                    id: "test",
                    fieldLabel: "テスト",
                    taxLine: .salesRevenue,
                    value: 1000,
                    section: .revenue
                )
            ],
            generatedAt: Date()
        )
        let errors = EtaxCharacterValidator.validateForm(form)
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateFormDetectsInvalidCharacterInValue() {
        let form = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: [
                EtaxField(
                    id: "declarant_name",
                    fieldLabel: "氏名",
                    taxLine: nil,
                    value: "山田🎉太郎",
                    section: .declarantInfo
                )
            ],
            generatedAt: Date()
        )

        let errors = EtaxCharacterValidator.validateForm(form)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].description.contains("declarant_name"))
    }
}
