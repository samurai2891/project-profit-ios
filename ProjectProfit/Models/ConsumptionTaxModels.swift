import Foundation

/// 消費税レポートの集計結果
struct ConsumptionTaxSummary {
    let fiscalYear: Int
    let generatedAt: Date
    let outputTaxTotal: Int      // 仮受消費税合計（売上に対する消費税）
    let inputTaxTotal: Int       // 仮払消費税合計（仕入・経費に対する消費税）
    let taxPayable: Int          // 未払消費税 = outputTax - inputTax

    /// 納付税額（マイナスの場合は還付）
    var isRefund: Bool { taxPayable < 0 }
}
