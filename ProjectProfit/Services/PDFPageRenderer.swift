import PDFKit
import UIKit

/// PDFの先頭ページをUIImageとしてレンダリングするユーティリティ
enum PDFPageRenderer {
    struct RenderResult: Sendable {
        let image: UIImage
        let originalData: Data
        let pageCount: Int
    }

    private static let renderScale: CGFloat = 2.0

    /// PDFデータの先頭ページをUIImageとしてレンダリングする
    /// - Parameter pdfData: PDFファイルのバイナリデータ
    /// - Returns: レンダリング結果。無効なPDFの場合はnil
    static func renderFirstPage(from pdfData: Data) -> RenderResult? {
        guard let document = PDFDocument(data: pdfData),
              let page = document.page(at: 0) else { return nil }

        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(
            width: bounds.width * renderScale,
            height: bounds.height * renderScale
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: renderScale, y: -renderScale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }

        return RenderResult(
            image: image,
            originalData: pdfData,
            pageCount: document.pageCount
        )
    }
}
