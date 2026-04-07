import Foundation
import os

struct SharedImportInboxItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalFilename: String
    let storedFilename: String
    let typeIdentifier: String
    let createdAt: Date
}

enum ShareImportQueueDiagnosticCode: String, Codable, Equatable, Sendable {
    case sharedDefaultsUnavailable
    case sharedContainerUnavailable
    case queueDecodeFailed
    case orphanedEntriesPruned
    case queuePersistenceFailed
    case fileRemovalFailed
}

struct ShareImportQueueDiagnostic: Codable, Equatable, Sendable {
    let code: ShareImportQueueDiagnosticCode
    let message: String
    let removedCount: Int?
    let timestamp: Date
}

struct ShareImportQueueState: Equatable, Sendable {
    let items: [SharedImportInboxItem]
    let diagnostic: ShareImportQueueDiagnostic?
}

enum ShareImportInboxService {
    static let appGroupIdentifier = "group.com.projectprofit.ProjectProfit"

    private static let logger = Logger(subsystem: "com.projectprofit", category: "ShareImportInbox")
    private static let queueDefaultsKey = "shareImportQueue.v1"
    private static let inboxDirectoryName = "ShareInbox"
    private static var defaultsProvider: () -> UserDefaults? = {
        UserDefaults(suiteName: appGroupIdentifier)
    }
    private static var sharedContainerURLProvider: () -> URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
    private static var lastDiagnostic: ShareImportQueueDiagnostic?

    static func pendingCount() -> Int {
        pendingState().items.count
    }

    static func oldestItem() -> SharedImportInboxItem? {
        pendingState().items.first
    }

    static func pendingState() -> ShareImportQueueState {
        let result = normalizedQueue()
        if let diagnostic = result.diagnostic {
            updateDiagnostic(diagnostic)
        } else {
            clearLatestDiagnostic()
        }
        return ShareImportQueueState(items: result.items, diagnostic: result.diagnostic)
    }

    static func latestDiagnostic() -> ShareImportQueueDiagnostic? {
        lastDiagnostic
    }

    static func clearLatestDiagnostic() {
        lastDiagnostic = nil
    }

    static func fileURL(for item: SharedImportInboxItem) -> URL? {
        guard let directoryURL = sharedInboxDirectoryURL(createIfNeeded: false) else {
            return nil
        }
        let url = directoryURL.appendingPathComponent(item.storedFilename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    static func markConsumed(_ item: SharedImportInboxItem) {
        guard let fileURL = fileURL(for: item) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
            removeFromQueue(item)
        } catch {
            logger.warning("Failed to remove consumed shared file: \(error.localizedDescription)")
            updateDiagnostic(
                ShareImportQueueDiagnostic(
                    code: .fileRemovalFailed,
                    message: "共有ファイルの削除に失敗したため、受信キューを保持しました。",
                    removedCount: nil,
                    timestamp: Date()
                )
            )
        }
    }

    private static func normalizedQueue() -> (items: [SharedImportInboxItem], diagnostic: ShareImportQueueDiagnostic?) {
        let queueResult = loadQueue()
        let queue = queueResult.items
        guard !queue.isEmpty else {
            return ([], queueResult.diagnostic)
        }

        guard sharedInboxDirectoryURL(createIfNeeded: false) != nil else {
            return (
                queue.sorted { $0.createdAt < $1.createdAt },
                ShareImportQueueDiagnostic(
                    code: .sharedContainerUnavailable,
                    message: "共有保存領域にアクセスできないため、受信キューの整合確認を保留しました。",
                    removedCount: nil,
                    timestamp: Date()
                )
            )
        }

        var filtered: [SharedImportInboxItem] = []
        filtered.reserveCapacity(queue.count)

        for item in queue {
            if fileURL(for: item) != nil {
                filtered.append(item)
            }
        }

        var diagnostic = queueResult.diagnostic
        if filtered.count != queue.count {
            diagnostic = ShareImportQueueDiagnostic(
                code: .orphanedEntriesPruned,
                message: "Shared import queue contained missing files and was compacted.",
                removedCount: queue.count - filtered.count,
                timestamp: Date()
            )
            if let persistDiagnostic = persistQueue(filtered) {
                diagnostic = persistDiagnostic
            }
        }

        return (filtered.sorted { $0.createdAt < $1.createdAt }, diagnostic)
    }

    private static func loadQueue() -> (items: [SharedImportInboxItem], diagnostic: ShareImportQueueDiagnostic?) {
        guard let defaults = defaultsProvider() else {
            return ([], ShareImportQueueDiagnostic(
                code: .sharedDefaultsUnavailable,
                message: "UserDefaults for app group is unavailable.",
                removedCount: nil,
                timestamp: Date()
            ))
        }

        guard let data = defaults.data(forKey: queueDefaultsKey) else {
            return ([], nil)
        }

        do {
            return (try JSONDecoder().decode([SharedImportInboxItem].self, from: data), nil)
        } catch {
            logger.warning("Failed to decode shared import queue: \(error.localizedDescription)")
            return ([], ShareImportQueueDiagnostic(
                code: .queueDecodeFailed,
                message: "共有取り込みキューの読込に失敗しました。既存キューは保持したままです。",
                removedCount: nil,
                timestamp: Date()
            ))
        }
    }

    private static func persistQueue(_ queue: [SharedImportInboxItem]) -> ShareImportQueueDiagnostic? {
        guard let defaults = defaultsProvider() else {
            return ShareImportQueueDiagnostic(
                code: .sharedDefaultsUnavailable,
                message: "UserDefaults for app group is unavailable.",
                removedCount: nil,
                timestamp: Date()
            )
        }

        do {
            let data = try JSONEncoder().encode(queue)
            defaults.set(data, forKey: queueDefaultsKey)
            return nil
        } catch {
            logger.warning("Failed to encode shared import queue: \(error.localizedDescription)")
            return ShareImportQueueDiagnostic(
                code: .queuePersistenceFailed,
                message: "Failed to persist shared import queue updates.",
                removedCount: nil,
                timestamp: Date()
            )
        }
    }

    private static func removeFromQueue(_ item: SharedImportInboxItem) {
        let state = pendingState()
        let queue = state.items.filter { $0.id != item.id }
        if let diagnostic = persistQueue(queue) {
            updateDiagnostic(diagnostic)
        }
    }

    private static func updateDiagnostic(_ diagnostic: ShareImportQueueDiagnostic) {
        lastDiagnostic = diagnostic
    }

    private static func sharedInboxDirectoryURL(createIfNeeded: Bool) -> URL? {
        guard let containerURL = sharedContainerURLProvider() else {
            return nil
        }
        let directoryURL = containerURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)

        if createIfNeeded, !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                logger.warning("Failed to create shared inbox directory: \(error.localizedDescription)")
                return nil
            }
        }

        return directoryURL
    }

#if DEBUG
    static func configureForTesting(
        defaultsProvider: @escaping () -> UserDefaults?,
        sharedContainerURLProvider: @escaping () -> URL?
    ) {
        self.defaultsProvider = defaultsProvider
        self.sharedContainerURLProvider = sharedContainerURLProvider
        clearLatestDiagnostic()
    }

    static func resetTestingConfiguration() {
        defaultsProvider = { UserDefaults(suiteName: appGroupIdentifier) }
        sharedContainerURLProvider = {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        }
        clearLatestDiagnostic()
    }
#endif
}
