import XCTest
@testable import ProjectProfit

final class ProfileSettingsViewTests: XCTestCase {
    func testSecureStoreFailureMessageIsDefined() {
        XCTAssertFalse(ProfileSettingsView.secureStoreFailureMessage.isEmpty)
        XCTAssertTrue(ProfileSettingsView.secureStoreFailureMessage.contains("Keychain"))
        XCTAssertTrue(ProfileSettingsView.secureStoreFailureMessage.contains("平文では保存していません"))
    }
}
