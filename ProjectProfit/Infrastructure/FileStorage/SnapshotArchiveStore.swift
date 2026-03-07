import AppleArchive
import Foundation
import System

enum SnapshotArchiveStore {
    static func archiveDirectory(_ sourceDirectory: URL, to archiveURL: URL) throws {
        let fileManager = FileManager.default
        let parentDirectory = archiveURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        try ArchiveByteStream.withFileStream(
            path: FilePath(archiveURL.path),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: .ownerReadWrite
        ) { fileStream in
            try ArchiveByteStream.withCompressionStream(
                using: .lzfse,
                writingTo: fileStream
            ) { compressedStream in
                try ArchiveStream.withEncodeStream(writingTo: compressedStream) { encodeStream in
                    try encodeStream.writeDirectoryContents(
                        archiveFrom: FilePath(sourceDirectory.path),
                        keySet: .defaultForArchive
                    )
                }
            }
        }
    }

    static func extractArchive(at archiveURL: URL, to destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.removeItem(at: destinationDirectory)
        }
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        try ArchiveByteStream.withFileStream(
            path: FilePath(archiveURL.path),
            mode: .readOnly,
            options: [],
            permissions: .ownerReadWrite
        ) { fileStream in
            try ArchiveByteStream.withDecompressionStream(readingFrom: fileStream) { decompressedStream in
                try ArchiveStream.withDecodeStream(readingFrom: decompressedStream) { decodeStream in
                    try ArchiveStream.withExtractStream(extractingTo: FilePath(destinationDirectory.path)) { extractStream in
                        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
                    }
                }
            }
        }
    }
}
