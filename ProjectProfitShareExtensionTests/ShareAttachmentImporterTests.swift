import XCTest
import UniformTypeIdentifiers

final class ShareAttachmentImporterTests: XCTestCase {
    func testImportFileRepresentationCopiesBeforeTemporaryFileIsDeleted() async throws {
        let inboxDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: inboxDirectory) }

        let importedFile = try await ShareAttachmentImporter.importFileRepresentation(
            loadFileRepresentation: { completion in
                let sourceURL = inboxDirectory.appendingPathComponent("provider-temp.jpg")
                try? Data("provider-file".utf8).write(to: sourceURL, options: .atomic)
                completion(sourceURL, nil)
                try? FileManager.default.removeItem(at: sourceURL)
            },
            suggestedName: "shared-from-files",
            typeIdentifier: "public.jpeg",
            inboxDirectory: inboxDirectory
        )

        let file = try XCTUnwrap(importedFile)
        let savedURL = inboxDirectory.appendingPathComponent(file.storedFilename)

        XCTAssertEqual(file.originalFilename, "shared-from-files.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertEqual(try Data(contentsOf: savedURL), Data("provider-file".utf8))
    }

    func testSuggestedOriginalFilenameAppendsMissingExtension() {
        let filename = ShareAttachmentImporter.suggestedOriginalFilename(
            suggestedName: "statement-export",
            pathExtension: "pdf",
            fallbackStem: "shared"
        )

        XCTAssertEqual(filename, "statement-export.pdf")
    }

    func testImportFileRepresentationReturnsNilForItemProviderDomainError() async throws {
        let inboxDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: inboxDirectory) }

        let importedFile = try await ShareAttachmentImporter.importFileRepresentation(
            loadFileRepresentation: { completion in
                completion(nil, NSError(domain: NSItemProvider.errorDomain, code: -1))
            },
            suggestedName: "fallback-image",
            typeIdentifier: UTType.image.identifier,
            inboxDirectory: inboxDirectory
        )

        XCTAssertNil(importedFile)
    }
}
