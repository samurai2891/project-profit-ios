import XCTest
import UIKit
@testable import ProjectProfit

final class ReceiptImageStoreTests: XCTestCase {
    private var savedFileNames: [String] = []

    override func tearDown() {
        // Clean up test images
        for fileName in savedFileNames {
            ReceiptImageStore.deleteImage(fileName: fileName)
        }
        savedFileNames = []
        super.tearDown()
    }

    // MARK: - Directory

    func testEnsureDirectoryExists() {
        XCTAssertNoThrow(try ReceiptImageStore.ensureDirectoryExists())
    }

    // MARK: - Save & Load

    func testSaveAndLoadImage() throws {
        let image = createTestImage()
        let fileName = try ReceiptImageStore.saveImage(image)
        savedFileNames.append(fileName)

        XCTAssertFalse(fileName.isEmpty)
        XCTAssertTrue(fileName.hasSuffix(".jpg"))

        let loaded = ReceiptImageStore.loadImage(fileName: fileName)
        XCTAssertNotNil(loaded)
    }

    func testSaveCreatesUniqueFileNames() throws {
        let image = createTestImage()
        let fileName1 = try ReceiptImageStore.saveImage(image)
        let fileName2 = try ReceiptImageStore.saveImage(image)
        savedFileNames.append(contentsOf: [fileName1, fileName2])

        XCTAssertNotEqual(fileName1, fileName2)
    }

    // MARK: - Load Nonexistent

    func testLoadNonexistentImageReturnsNil() {
        let result = ReceiptImageStore.loadImage(fileName: "nonexistent-file.jpg")
        XCTAssertNil(result)
    }

    // MARK: - Delete

    func testDeleteImage() throws {
        let image = createTestImage()
        let fileName = try ReceiptImageStore.saveImage(image)

        XCTAssertTrue(ReceiptImageStore.imageExists(fileName: fileName))

        ReceiptImageStore.deleteImage(fileName: fileName)

        XCTAssertFalse(ReceiptImageStore.imageExists(fileName: fileName))
        XCTAssertNil(ReceiptImageStore.loadImage(fileName: fileName))
    }

    func testDeleteNonexistentImageDoesNotThrow() {
        // Should not throw or crash
        ReceiptImageStore.deleteImage(fileName: "nonexistent.jpg")
    }

    // MARK: - Exists

    func testImageExistsReturnsTrue() throws {
        let image = createTestImage()
        let fileName = try ReceiptImageStore.saveImage(image)
        savedFileNames.append(fileName)

        XCTAssertTrue(ReceiptImageStore.imageExists(fileName: fileName))
    }

    func testImageExistsReturnsFalse() {
        XCTAssertFalse(ReceiptImageStore.imageExists(fileName: "definitely-not-here.jpg"))
    }

    // MARK: - Path Traversal Prevention

    func testLoadImage_rejectsPathTraversal() {
        let result = ReceiptImageStore.loadImage(fileName: "../../etc/passwd")
        XCTAssertNil(result)
    }

    func testDeleteImage_rejectsPathTraversal() {
        // Should not crash or delete anything outside the directory
        ReceiptImageStore.deleteImage(fileName: "../../../important.txt")
    }

    func testImageExists_rejectsBackslash() {
        let result = ReceiptImageStore.imageExists(fileName: "..\\..\\etc")
        XCTAssertFalse(result)
    }

    func testImageExists_rejectsEmpty() {
        let result = ReceiptImageStore.imageExists(fileName: "")
        XCTAssertFalse(result)
    }

    func testSaveAndLoad_worksWithSanitization() throws {
        let image = createTestImage()
        let fileName = try ReceiptImageStore.saveImage(image)
        savedFileNames.append(fileName)

        // UUID-based filename should pass sanitization
        XCTAssertNotNil(ReceiptImageStore.sanitizedFileName(fileName))
        XCTAssertNotNil(ReceiptImageStore.loadImage(fileName: fileName))
        XCTAssertTrue(ReceiptImageStore.imageExists(fileName: fileName))
    }

    func testSanitizedFileName_rejectsDotDot() {
        XCTAssertNil(ReceiptImageStore.sanitizedFileName(".."))
    }

    func testSanitizedFileName_rejectsDot() {
        XCTAssertNil(ReceiptImageStore.sanitizedFileName("."))
    }

    func testSanitizedFileName_acceptsValidUUID() {
        let validName = "\(UUID().uuidString).jpg"
        XCTAssertEqual(ReceiptImageStore.sanitizedFileName(validName), validName)
    }

    // MARK: - Helpers

    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
