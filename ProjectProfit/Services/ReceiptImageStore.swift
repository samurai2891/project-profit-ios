import Foundation
import UIKit

// MARK: - Receipt Image Store

enum ReceiptImageStore {
    private static let directoryName = "ReceiptImages"
    private static let jpegQuality: CGFloat = 0.7

    // MARK: - Directory

    private static var directoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(directoryName)
    }

    static func ensureDirectoryExists() throws {
        let url = directoryURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save

    static func saveImage(_ image: UIImage) throws -> String {
        try ensureDirectoryExists()

        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw ReceiptImageStoreError.compressionFailed
        }

        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    // MARK: - Load

    static func loadImage(fileName: String) -> UIImage? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    // MARK: - Delete

    static func deleteImage(fileName: String) {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Exists

    static func imageExists(fileName: String) -> Bool {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}

// MARK: - Error

enum ReceiptImageStoreError: LocalizedError {
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            "画像の圧縮に失敗しました"
        }
    }
}
