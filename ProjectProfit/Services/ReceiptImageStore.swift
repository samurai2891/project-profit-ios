import Foundation
import CryptoKit
import UIKit

// MARK: - Receipt Image Store

enum ReceiptImageStore {
    private static let directoryName = "ReceiptImages"
    private static let documentDirectoryName = "DocumentFiles"
    private static let jpegQuality: CGFloat = 0.7

    // MARK: - Directory

    private static var directoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(directoryName)
    }

    private static var documentDirectoryURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(documentDirectoryName)
    }

    static func ensureDirectoryExists() throws {
        let url = directoryURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func ensureDocumentDirectoryExists() throws {
        let url = documentDirectoryURL
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

    // MARK: - Sanitization

    /// パストラバーサルを防止。ファイル名のみを抽出し、パス区切り文字を拒否。
    static func sanitizedFileName(_ fileName: String) -> String? {
        let lastComponent = (fileName as NSString).lastPathComponent
        guard !lastComponent.isEmpty,
              lastComponent != ".",
              lastComponent != "..",
              !fileName.contains("/"),
              !fileName.contains("\\")
        else { return nil }
        return lastComponent
    }

    // MARK: - Load

    static func loadImage(fileName: String) -> UIImage? {
        guard let safeName = sanitizedFileName(fileName) else { return nil }
        let fileURL = directoryURL.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    static func loadImageData(fileName: String) -> Data? {
        guard let safeName = sanitizedFileName(fileName) else { return nil }
        let fileURL = directoryURL.appendingPathComponent(safeName)
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Delete

    static func deleteImage(fileName: String) {
        guard let safeName = sanitizedFileName(fileName) else { return }
        let fileURL = directoryURL.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Exists

    static func imageExists(fileName: String) -> Bool {
        guard let safeName = sanitizedFileName(fileName) else { return false }
        let fileURL = directoryURL.appendingPathComponent(safeName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Document File Save

    static func saveDocumentData(_ data: Data, originalFileName: String) throws -> String {
        try ensureDocumentDirectoryExists()
        let ext = (originalFileName as NSString).pathExtension
        let normalizedExtension = ext.isEmpty ? "bin" : ext.lowercased()
        let fileName = "\(UUID().uuidString).\(normalizedExtension)"
        let fileURL = documentDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileName
    }

    static func loadDocumentData(fileName: String) -> Data? {
        guard let safeName = sanitizedFileName(fileName) else { return nil }
        let fileURL = documentDirectoryURL.appendingPathComponent(safeName)
        return try? Data(contentsOf: fileURL)
    }

    static func deleteDocumentFile(fileName: String) {
        guard let safeName = sanitizedFileName(fileName) else { return }
        let fileURL = documentDirectoryURL.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func documentFileExists(fileName: String) -> Bool {
        guard let safeName = sanitizedFileName(fileName) else { return false }
        let fileURL = documentDirectoryURL.appendingPathComponent(safeName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func documentFileURL(fileName: String) -> URL? {
        guard let safeName = sanitizedFileName(fileName) else { return nil }
        let fileURL = documentDirectoryURL.appendingPathComponent(safeName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
