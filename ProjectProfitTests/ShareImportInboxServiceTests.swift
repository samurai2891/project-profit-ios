import Foundation
import XCTest
@testable import ProjectProfit

final class ShareImportInboxServiceTests: XCTestCase {
    private let queueDefaultsKey = "shareImportQueue.v1"
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var tempDirectoryURL: URL!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ShareImportInboxServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareImportInboxServiceTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        ShareImportInboxService.configureForTesting(
            defaultsProvider: { [weak self] in self?.defaults },
            sharedContainerURLProvider: { [weak self] in self?.tempDirectoryURL }
        )
    }

    override func tearDown() {
        ShareImportInboxService.resetTestingConfiguration()

        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }

        defaults = nil
        defaultsSuiteName = nil
        tempDirectoryURL = nil
        super.tearDown()
    }

    func testPendingStateCorruptedQueueReturnsDecodeDiagnostic() {
        defaults.set(Data("broken-json".utf8), forKey: queueDefaultsKey)

        let state = ShareImportInboxService.pendingState()

        XCTAssertTrue(state.items.isEmpty)
        XCTAssertEqual(state.diagnostic?.code, .queueDecodeFailed)
        XCTAssertEqual(ShareImportInboxService.latestDiagnostic()?.code, .queueDecodeFailed)
        XCTAssertNotNil(defaults.data(forKey: queueDefaultsKey))
    }

    func testPendingStatePrunesOrphanedEntriesAndPersistsCompactedQueue() throws {
        let existingItem = makeItem(filename: "existing.pdf", createdAt: Date(timeIntervalSince1970: 100))
        let missingItem = makeItem(filename: "missing.pdf", createdAt: Date(timeIntervalSince1970: 200))

        let existingFileURL = tempDirectoryURL
            .appendingPathComponent("ShareInbox", isDirectory: true)
            .appendingPathComponent(existingItem.storedFilename)
        try FileManager.default.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("dummy".utf8).write(to: existingFileURL)

        let encoded = try JSONEncoder().encode([existingItem, missingItem])
        defaults.set(encoded, forKey: queueDefaultsKey)

        let state = ShareImportInboxService.pendingState()
        let persisted = try XCTUnwrap(defaults.data(forKey: queueDefaultsKey))
        let persistedItems = try JSONDecoder().decode([SharedImportInboxItem].self, from: persisted)

        XCTAssertEqual(state.items, [existingItem])
        XCTAssertEqual(state.diagnostic?.code, .orphanedEntriesPruned)
        XCTAssertEqual(state.diagnostic?.removedCount, 1)
        XCTAssertEqual(persistedItems, [existingItem])
    }

    func testPendingStateDefaultsUnavailableSurfacesDiagnostic() {
        ShareImportInboxService.configureForTesting(
            defaultsProvider: { nil },
            sharedContainerURLProvider: { [weak self] in self?.tempDirectoryURL }
        )

        let state = ShareImportInboxService.pendingState()

        XCTAssertTrue(state.items.isEmpty)
        XCTAssertEqual(state.diagnostic?.code, .sharedDefaultsUnavailable)
        XCTAssertEqual(ShareImportInboxService.latestDiagnostic()?.code, .sharedDefaultsUnavailable)
        XCTAssertEqual(ShareImportInboxService.pendingCount(), 0)
        XCTAssertNil(ShareImportInboxService.oldestItem())
    }

    func testPendingStateSharedContainerUnavailableKeepsQueue() throws {
        let item = makeItem(filename: "existing.pdf", createdAt: Date())
        defaults.set(try JSONEncoder().encode([item]), forKey: queueDefaultsKey)

        ShareImportInboxService.configureForTesting(
            defaultsProvider: { [weak self] in self?.defaults },
            sharedContainerURLProvider: { nil }
        )

        let state = ShareImportInboxService.pendingState()

        XCTAssertEqual(state.items, [item])
        XCTAssertEqual(state.diagnostic?.code, .sharedContainerUnavailable)
    }

    private func makeItem(filename: String, createdAt: Date) -> SharedImportInboxItem {
        SharedImportInboxItem(
            id: UUID(),
            originalFilename: filename,
            storedFilename: filename,
            typeIdentifier: "public.pdf",
            createdAt: createdAt
        )
    }
}
