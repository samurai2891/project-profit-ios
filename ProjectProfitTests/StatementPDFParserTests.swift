import PDFKit
import UIKit
import XCTest
@testable import ProjectProfit

@MainActor
final class StatementPDFParserTests: XCTestCase {
    func testParseExtractsLinesFromMultipageTextPDF() async throws {
        let parser = StatementPDFParser()
        let pdfData = makeTextPDF(pages: [
            "2026/01/10 ClientDeposit 120000",
            "2026/01/12 CoffeeShop -5500"
        ])

        let drafts = try await parser.parse(fileData: pdfData, fallbackYear: 2026)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].description, "ClientDeposit")
        XCTAssertEqual(drafts[0].direction, .inflow)
        XCTAssertEqual(drafts[1].direction, .outflow)
        XCTAssertEqual(drafts[1].amount, Decimal(5500))
    }

    func testParseFallsBackToOCRForImageOnlyPDF() async throws {
        let parser = StatementPDFParser()
        let image = makeImage(text: "2026/01/15 Taxi -1200")
        let pdfData = makeImagePDF(image: image)

        let drafts = try await parser.parse(fileData: pdfData, fallbackYear: 2026)

        XCTAssertFalse(drafts.isEmpty)
        XCTAssertEqual(drafts.first?.direction, .outflow)
    }

    private func makeTextPDF(pages: [String]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 28, weight: .regular),
                    .foregroundColor: UIColor.black,
                ]
                page.draw(in: CGRect(x: 40, y: 120, width: 500, height: 60), withAttributes: attrs)
            }
        }
    }

    private func makeImage(text: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 400))
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1200, height: 400)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.black,
            ]
            text.draw(in: CGRect(x: 40, y: 120, width: 1100, height: 120), withAttributes: attrs)
        }
    }

    private func makeImagePDF(image: UIImage) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(x: 20, y: 120, width: 555, height: 185))
        }
    }
}
