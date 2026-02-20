import XCTest
@testable import ProjectProfit

final class LineItemTests: XCTestCase {

    // MARK: - LineItem

    func testLineItemDefaultQuantity() {
        let item = LineItem(name: "コーヒー", unitPrice: 350)
        XCTAssertEqual(item.name, "コーヒー")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.unitPrice, 350)
        XCTAssertEqual(item.subtotal, 350)
    }

    func testLineItemWithQuantity() {
        let item = LineItem(name: "ボールペン", quantity: 3, unitPrice: 100)
        XCTAssertEqual(item.quantity, 3)
        XCTAssertEqual(item.unitPrice, 100)
        XCTAssertEqual(item.subtotal, 300)
    }

    func testLineItemWithExplicitSubtotal() {
        let item = LineItem(name: "割引品", quantity: 2, unitPrice: 500, subtotal: 900)
        XCTAssertEqual(item.subtotal, 900)
    }

    func testLineItemEquality() {
        let a = LineItem(name: "A", unitPrice: 100)
        let b = LineItem(name: "A", unitPrice: 100)
        XCTAssertEqual(a, b)
    }

    func testLineItemInequality() {
        let a = LineItem(name: "A", unitPrice: 100)
        let b = LineItem(name: "B", unitPrice: 100)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ReceiptLineItem

    func testReceiptLineItemDefaultQuantity() {
        let item = ReceiptLineItem(name: "コピー用紙", unitPrice: 450)
        XCTAssertEqual(item.name, "コピー用紙")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.unitPrice, 450)
        XCTAssertEqual(item.subtotal, 450)
    }

    func testReceiptLineItemWithQuantity() {
        let item = ReceiptLineItem(name: "トナー", quantity: 2, unitPrice: 3000)
        XCTAssertEqual(item.subtotal, 6000)
    }

    func testReceiptLineItemWithExplicitSubtotal() {
        let item = ReceiptLineItem(name: "セール品", quantity: 1, unitPrice: 1000, subtotal: 800)
        XCTAssertEqual(item.subtotal, 800)
    }

    func testReceiptLineItemEquality() {
        let a = ReceiptLineItem(name: "A", quantity: 2, unitPrice: 100)
        let b = ReceiptLineItem(name: "A", quantity: 2, unitPrice: 100)
        XCTAssertEqual(a, b)
    }

    // MARK: - EditableLineItem

    func testEditableLineItemDefaults() {
        let item = EditableLineItem()
        XCTAssertEqual(item.name, "")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.unitPrice, 0)
        XCTAssertEqual(item.subtotal, 0)
    }

    func testEditableLineItemFromLineItem() {
        let lineItem = LineItem(name: "テスト品", quantity: 3, unitPrice: 200)
        let editable = EditableLineItem(from: lineItem)
        XCTAssertEqual(editable.name, "テスト品")
        XCTAssertEqual(editable.quantity, 3)
        XCTAssertEqual(editable.unitPrice, 200)
        XCTAssertEqual(editable.subtotal, 600)
    }

    func testEditableLineItemToLineItem() {
        var editable = EditableLineItem()
        editable.name = "変換テスト"
        editable.quantity = 2
        editable.unitPrice = 150

        let lineItem = editable.toLineItem()
        XCTAssertEqual(lineItem.name, "変換テスト")
        XCTAssertEqual(lineItem.quantity, 2)
        XCTAssertEqual(lineItem.unitPrice, 150)
        XCTAssertEqual(lineItem.subtotal, 300)
    }

    func testEditableLineItemToReceiptLineItem() {
        var editable = EditableLineItem()
        editable.name = "変換テスト"
        editable.quantity = 5
        editable.unitPrice = 100

        let receiptItem = editable.toReceiptLineItem()
        XCTAssertEqual(receiptItem.name, "変換テスト")
        XCTAssertEqual(receiptItem.quantity, 5)
        XCTAssertEqual(receiptItem.unitPrice, 100)
        XCTAssertEqual(receiptItem.subtotal, 500)
    }

    func testEditableLineItemSubtotalComputed() {
        var item = EditableLineItem()
        item.quantity = 3
        item.unitPrice = 250
        XCTAssertEqual(item.subtotal, 750)

        item.quantity = 1
        XCTAssertEqual(item.subtotal, 250)
    }

    // MARK: - ReceiptData with LineItems

    func testReceiptDataWithLineItems() {
        let items = [
            LineItem(name: "コーヒー", unitPrice: 350),
            LineItem(name: "サンドイッチ", unitPrice: 480),
        ]
        let data = ReceiptData(
            totalAmount: 830,
            date: "2026-01-15",
            storeName: "テストカフェ",
            estimatedCategory: "supplies",
            itemSummary: "",
            lineItems: items
        )
        XCTAssertEqual(data.lineItems.count, 2)
        XCTAssertEqual(data.lineItems[0].name, "コーヒー")
        XCTAssertEqual(data.lineItems[1].name, "サンドイッチ")
    }

    func testReceiptDataFormattedMemoWithLineItems() {
        let items = [
            LineItem(name: "コーヒー", unitPrice: 350),
            LineItem(name: "サンドイッチ", unitPrice: 480),
        ]
        let data = ReceiptData(
            totalAmount: 830,
            date: "2026-01-15",
            storeName: "テストカフェ",
            estimatedCategory: "supplies",
            itemSummary: "旧サマリー",
            lineItems: items
        )
        // When lineItems exist, memo should use item names instead of itemSummary
        XCTAssertTrue(data.formattedMemo.contains("コーヒー"))
        XCTAssertTrue(data.formattedMemo.contains("サンドイッチ"))
        XCTAssertFalse(data.formattedMemo.contains("旧サマリー"))
    }

    func testReceiptDataFormattedMemoFallsBackToSummary() {
        let data = ReceiptData(
            totalAmount: 500,
            date: "2026-01-15",
            storeName: "テスト店",
            estimatedCategory: "supplies",
            itemSummary: "テスト品目",
            lineItems: []
        )
        XCTAssertTrue(data.formattedMemo.contains("テスト品目"))
    }

    func testReceiptDataDefaultLineItemsEmpty() {
        let data = ReceiptData(
            totalAmount: 100,
            date: "2026-01-01",
            storeName: "",
            estimatedCategory: "other-expense",
            itemSummary: ""
        )
        XCTAssertTrue(data.lineItems.isEmpty)
    }
}
