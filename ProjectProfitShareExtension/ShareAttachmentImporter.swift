import Foundation
import UniformTypeIdentifiers

struct ImportedShareFile: Equatable {
    let originalFilename: String
    let storedFilename: String
}

enum ShareAttachmentImporterError: LocalizedError {
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return message
        }
    }
}

enum ShareAttachmentImporter {
    typealias FileRepresentationLoader = (@escaping (URL?, Error?) -> Void) -> Void
    typealias FileCopyHandler = (URL, URL) throws -> Void

    static func importFileRepresentation(
        loadFileRepresentation: @escaping FileRepresentationLoader,
        suggestedName: String?,
        typeIdentifier: String,
        inboxDirectory: URL,
        copyItem: @escaping FileCopyHandler = replaceItem
    ) async throws -> ImportedShareFile? {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation { url, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == NSItemProvider.errorDomain {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: ShareAttachmentImporterError.loadFailed(error.localizedDescription))
                    return
                }

                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let fileExtension = normalizedFileExtension(
                        pathExtension: url.pathExtension,
                        typeIdentifier: typeIdentifier
                    )
                    let storedFilename = "\(UUID().uuidString).\(fileExtension)"
                    let destinationURL = inboxDirectory.appendingPathComponent(storedFilename)
                    try copyItem(url, destinationURL)
                    continuation.resume(returning: ImportedShareFile(
                        originalFilename: suggestedOriginalFilename(
                            suggestedName: suggestedName,
                            pathExtension: fileExtension,
                            fallbackStem: url.deletingPathExtension().lastPathComponent
                        ),
                        storedFilename: storedFilename
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func suggestedOriginalFilename(
        suggestedName: String?,
        pathExtension: String,
        fallbackStem: String
    ) -> String {
        let trimmedSuggestedName = suggestedName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSuggestedName.isEmpty else {
            return "\(fallbackStem).\(pathExtension)"
        }

        let currentExtension = (trimmedSuggestedName as NSString).pathExtension
        if currentExtension.isEmpty {
            return "\(trimmedSuggestedName).\(pathExtension)"
        }
        return trimmedSuggestedName
    }

    static func normalizedFileExtension(pathExtension: String, typeIdentifier: String) -> String {
        if !pathExtension.isEmpty {
            return pathExtension.lowercased()
        }
        if let utType = UTType(typeIdentifier),
           let preferredExtension = utType.preferredFilenameExtension {
            return preferredExtension.lowercased()
        }
        return typeIdentifier == UTType.pdf.identifier ? "pdf" : "jpg"
    }

    static func replaceItem(_ sourceURL: URL, _ destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}
