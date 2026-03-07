import Foundation

/// 消費税レポートの集計結果
struct ConsumptionTaxSummary {
    let fiscalYear: Int
    let generatedAt: Date
    let outputTaxTotal: Int      // 仮受消費税合計（売上に対する消費税）
    let inputTaxTotal: Int       // 控除対象の仮払消費税合計
    let rawInputTaxTotal: Int    // 勘定科目上の仮払消費税合計
    let taxPayable: Int          // 未払消費税 = outputTax - deductible input tax

    /// 納付税額（マイナスの場合は還付）
    var isRefund: Bool { taxPayable < 0 }

    init(
        fiscalYear: Int,
        generatedAt: Date,
        outputTaxTotal: Int,
        inputTaxTotal: Int,
        rawInputTaxTotal: Int? = nil,
        taxPayable: Int
    ) {
        self.fiscalYear = fiscalYear
        self.generatedAt = generatedAt
        self.outputTaxTotal = outputTaxTotal
        self.inputTaxTotal = inputTaxTotal
        self.rawInputTaxTotal = rawInputTaxTotal ?? inputTaxTotal
        self.taxPayable = taxPayable
    }
}
