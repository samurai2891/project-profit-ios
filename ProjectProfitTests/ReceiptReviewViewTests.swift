import UIKit
import XCTest
@testable import ProjectProfit

@MainActor
final class ReceiptReviewViewTests: XCTestCase {
    func testResolveFilePayloadPreservesOriginalImportedImageData() throws {
        let originalData = Data("original-image-data".utf8)

        let payload = try ReceiptReviewView.resolveFilePayload(
            evidenceSourceType: .importedImage,
            originalFileData: originalData,
            originalFileMimeType: "image/png",
            receiptImage: nil
        )

        XCTAssertEqual(payload.fileData, originalData)
        XCTAssertEqual(payload.mimeType, "image/png")
    }

    func testResolveFilePayloadFallsBackToJPEGWhenOriginalDataMissing() throws {
        let image = makeImage()

        let payload = try ReceiptReviewView.resolveFilePayload(
            evidenceSourceType: .photoLibrary,
            originalFileData: nil,
            originalFileMimeType: nil,
            receiptImage: image
        )

        XCTAssertEqual(payload.mimeType, "image/jpeg")
        XCTAssertFalse(payload.fileData.isEmpty)
    }

    func testFileExtensionUsesImportedImageMimeType() {
        let ext = ReceiptReviewView.fileExtension(
            evidenceSourceType: .importedImage,
            originalFileData: Data("image-bytes".utf8),
            originalFileMimeType: "image/png"
        )

        XCTAssertEqual(ext, "png")
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor.black.setFill()
            context.fill(CGRect(x: 4, y: 4, width: 8, height: 8))
        }
    }
}
