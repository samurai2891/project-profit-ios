@testable import ProjectProfit
import SwiftData
import XCTest

final class DataStoreYearLockGradedTests: XCTestCase {
    @MainActor
    func testAllowsNormalPostingStates() {
        // open and softClose allow normal posting
        XCTAssertTrue(YearLockState.open.allowsNormalPosting)
        XCTAssertTrue(YearLockState.softClose.allowsNormalPosting)
        // taxClose, filed, finalLock deny normal posting
        XCTAssertFalse(YearLockState.taxClose.allowsNormalPosting)
        XCTAssertFalse(YearLockState.filed.allowsNormalPosting)
        XCTAssertFalse(YearLockState.finalLock.allowsNormalPosting)
    }

    @MainActor
    func testAllowsAdjustingEntryStates() {
        // open, softClose, taxClose allow adjusting entries
        XCTAssertTrue(YearLockState.open.allowsAdjustingEntries)
        XCTAssertTrue(YearLockState.softClose.allowsAdjustingEntries)
        XCTAssertTrue(YearLockState.taxClose.allowsAdjustingEntries)
        // filed and finalLock deny adjusting entries
        XCTAssertFalse(YearLockState.filed.allowsAdjustingEntries)
        XCTAssertFalse(YearLockState.finalLock.allowsAdjustingEntries)
    }

    @MainActor
    func testIsFullyLocked() {
        XCTAssertFalse(YearLockState.open.isFullyLocked)
        XCTAssertFalse(YearLockState.softClose.isFullyLocked)
        XCTAssertFalse(YearLockState.taxClose.isFullyLocked)
        XCTAssertFalse(YearLockState.filed.isFullyLocked)
        XCTAssertTrue(YearLockState.finalLock.isFullyLocked)
    }
}
