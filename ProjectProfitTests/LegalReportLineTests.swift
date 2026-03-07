import XCTest
@testable import ProjectProfit

final class LegalReportLineTests: XCTestCase {

    func testAllCasesHaveDisplayNames() {
        for line in LegalReportLine.allCases {
            XCTAssertFalse(line.displayName.isEmpty, "\(line.rawValue) should have a display name")
        }
    }

    func testAllCasesHaveSections() {
        for line in LegalReportLine.allCases {
            // Should not crash
            _ = line.section
        }
    }

    func testRevenueLinesBelongToRevenueSection() {
        XCTAssertEqual(LegalReportLine.salesRevenue.section, .revenue)
        XCTAssertEqual(LegalReportLine.miscIncome.section, .revenue)
    }

    func testCostOfSalesLinesBelongToCostOfSalesSection() {
        XCTAssertEqual(LegalReportLine.openingInventory.section, .costOfSales)
        XCTAssertEqual(LegalReportLine.purchases.section, .costOfSales)
        XCTAssertEqual(LegalReportLine.closingInventory.section, .costOfSales)
    }

    func testExpenseLinesBelongToExpenseSection() {
        XCTAssertEqual(LegalReportLine.salaries.section, .expenses)
        XCTAssertEqual(LegalReportLine.depreciation.section, .expenses)
        XCTAssertEqual(LegalReportLine.rent.section, .expenses)
    }

    func testBalanceSheetLines() {
        XCTAssertEqual(LegalReportLine.cash.section, .balanceSheet)
        XCTAssertEqual(LegalReportLine.accountsPayable.section, .balanceSheet)
        XCTAssertEqual(LegalReportLine.capital.section, .balanceSheet)
    }

    func testRawValuesAreUnique() {
        let rawValues = LegalReportLine.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "All raw values should be unique")
    }

    func testRoundTripCoding() throws {
        for line in LegalReportLine.allCases {
            let data = try JSONEncoder().encode(line)
            let decoded = try JSONDecoder().decode(LegalReportLine.self, from: data)
            XCTAssertEqual(line, decoded)
        }
    }

    func testIdentifiableReturnsRawValue() {
        for line in LegalReportLine.allCases {
            XCTAssertEqual(line.id, line.rawValue)
        }
    }

    func testAllSectionsHaveAtLeastOneLine() {
        for section in LegalReportSection.allCases {
            let lines = LegalReportLine.allCases.filter { $0.section == section }
            XCTAssertFalse(lines.isEmpty, "\(section.rawValue) should have at least one line")
        }
    }
}
