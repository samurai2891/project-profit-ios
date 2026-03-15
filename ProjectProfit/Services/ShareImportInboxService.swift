import Foundation
import os

struct SharedImportInboxItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalFilename: String
    let storedFilename: String
    let typeIdentifier: String
    let createdAt: Date
}

enum ShareImportInboxService {
    static let appGroupIdentifier = "group.com.projectprofit.ProjectProfit"

    private static let logger = Logger(subsystem: "com.projectprofit", category: "ShareImportInbox")
    private static let queueDefaultsKey = "shareImportQueue.v1"
    private static let inboxDirectoryName = "ShareInbox"

    static func pendingCount() -> Int {
        normalizedQueue().count
    }

    static func oldestItem() -> SharedImportInboxItem? {
        normalizedQueue().first
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
        removeFromQueue(item)
        guard let fileURL = fileURL(for: item) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.warning("Failed to remove consumed shared file: \(error.localizedDescription)")
        }
    }

    private static func normalizedQueue() -> [SharedImportInboxItem] {
        let queue = loadQueue()
        guard !queue.isEmpty else { return [] }

        var filtered: [SharedImportInboxItem] = []
        filtered.reserveCapacity(queue.count)

        for item in queue {
            if fileURL(for: item) != nil {
                filtered.append(item)
            }
        }

        if filtered.count != queue.count {
            persistQueue(filtered)
        }

        return filtered.sorted { $0.createdAt < $1.createdAt }
    }

    private static func loadQueue() -> [SharedImportInboxItem] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: queueDefaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SharedImportInboxItem].self, from: data)
        } catch {
            logger.warning("Failed to decode shared import queue: \(error.localizedDescription)")
            defaults.removeObject(forKey: queueDefaultsKey)
            return []
        }
    }

    private static func persistQueue(_ queue: [SharedImportInboxItem]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        do {
            let data = try JSONEncoder().encode(queue)
            defaults.set(data, forKey: queueDefaultsKey)
        } catch {
            logger.warning("Failed to encode shared import queue: \(error.localizedDescription)")
        }
    }

    private static func removeFromQueue(_ item: SharedImportInboxItem) {
        let queue = normalizedQueue().filter { $0.id != item.id }
        persistQueue(queue)
    }

    private static func sharedInboxDirectoryURL(createIfNeeded: Bool) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
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
}
