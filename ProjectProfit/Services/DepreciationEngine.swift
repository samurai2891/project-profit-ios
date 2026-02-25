import Foundation
import os
import SwiftData

// MARK: - DepreciationCalculation

/// 1年度分の減価償却計算結果
struct DepreciationCalculation: Identifiable {
    let id = UUID()
    let assetId: UUID
    let fiscalYear: Int
    let annualAmount: Int           // 年間償却額
    let businessAmount: Int         // 事業使用分
    let personalAmount: Int         // 家事使用分
    let accumulatedDepreciation: Int // 累計償却額（当年度含む）
    let bookValueAfter: Int         // 償却後帳簿価額
}

// MARK: - DepreciationEngine

@MainActor
final class DepreciationEngine {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.projectprofit", category: "DepreciationEngine")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Pure Calculation

    /// 指定年度の減価償却額を計算する（副作用なし）
    /// - Returns: 計算結果、償却不要の場合は nil
    static func calculate(
        asset: PPFixedAsset,
        fiscalYear: Int,
        priorAccumulatedDepreciation: Int
    ) -> DepreciationCalculation? {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        let acquisitionMonth = calendar.component(.month, from: asset.acquisitionDate)

        // 取得年より前は償却不可
        guard fiscalYear >= acquisitionYear else { return nil }

        // 除却/売却済みの場合、除却年度以降は償却不可
        if let disposalDate = asset.disposalDate {
            let disposalYear = calendar.component(.year, from: disposalDate)
            if fiscalYear > disposalYear { return nil }
        }

        // 既に全額償却済み
        let maxDepreciation = asset.depreciableBasis
        guard priorAccumulatedDepreciation < maxDepreciation else { return nil }

        let remainingBasis = maxDepreciation - priorAccumulatedDepreciation
        let bookValueBefore = asset.acquisitionCost - priorAccumulatedDepreciation

        let rawAmount: Int
        switch asset.depreciationMethod {
        case .straightLine:
            rawAmount = calculateStraightLine(
                asset: asset,
                fiscalYear: fiscalYear,
                acquisitionYear: acquisitionYear,
                acquisitionMonth: acquisitionMonth,
                remainingBasis: remainingBasis
            )
        case .decliningBalance:
            rawAmount = calculateDecliningBalance(
                asset: asset,
                fiscalYear: fiscalYear,
                acquisitionYear: acquisitionYear,
                acquisitionMonth: acquisitionMonth,
                bookValueBefore: bookValueBefore,
                remainingBasis: remainingBasis
            )
        case .immediateExpense, .smallBusiness:
            rawAmount = calculateImmediateExpense(
                asset: asset,
                fiscalYear: fiscalYear,
                acquisitionYear: acquisitionYear,
                remainingBasis: remainingBasis
            )
        case .threeYearEqual:
            rawAmount = calculateThreeYearEqual(
                asset: asset,
                fiscalYear: fiscalYear,
                acquisitionYear: acquisitionYear,
                remainingBasis: remainingBasis
            )
        }

        guard rawAmount > 0 else { return nil }

        // 除却/売却年度は月割計算
        var adjustedAmount = rawAmount
        if let disposalDate = asset.disposalDate {
            let disposalYear = calendar.component(.year, from: disposalDate)
            if fiscalYear == disposalYear {
                let disposalMonth = calendar.component(.month, from: disposalDate)
                adjustedAmount = rawAmount * disposalMonth / 12
            }
        }

        // 上限キャップ: 残存可能額を超えない
        let cappedAmount = min(adjustedAmount, remainingBasis)

        // 事業使用割合で按分
        let businessAmount = cappedAmount * asset.businessUsePercent / 100
        let personalAmount = cappedAmount - businessAmount

        return DepreciationCalculation(
            assetId: asset.id,
            fiscalYear: fiscalYear,
            annualAmount: cappedAmount,
            businessAmount: businessAmount,
            personalAmount: personalAmount,
            accumulatedDepreciation: priorAccumulatedDepreciation + cappedAmount,
            bookValueAfter: asset.acquisitionCost - priorAccumulatedDepreciation - cappedAmount
        )
    }

    // MARK: - Journal Entry Generation

    /// 減価償却仕訳を生成する
    /// - Returns: 生成された仕訳、既存の場合は既存を返す
    @discardableResult
    func postDepreciation(
        asset: PPFixedAsset,
        fiscalYear: Int,
        priorAccumulated: Int,
        accounts: [PPAccount]
    ) -> PPJournalEntry? {
        let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: asset.id, year: fiscalYear)

        // 冪等性: 既存仕訳があればそれを返す
        let descriptor = FetchDescriptor<PPJournalEntry>(
            predicate: #Predicate<PPJournalEntry> { $0.sourceKey == sourceKey }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        guard let calc = Self.calculate(
            asset: asset,
            fiscalYear: fiscalYear,
            priorAccumulatedDepreciation: priorAccumulated
        ) else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        guard let entryDate = calendar.date(from: DateComponents(year: fiscalYear, month: 12, day: 31)) else {
            return nil
        }

        let entry = PPJournalEntry(
            sourceKey: sourceKey,
            date: entryDate,
            entryType: .auto,
            memo: "\(asset.name) \(fiscalYear)年 減価償却",
            isPosted: false
        )
        modelContext.insert(entry)

        var order = 0

        // 借方: 減価償却費（事業使用分）
        if calc.businessAmount > 0 {
            let expenseLine = PPJournalLine(
                entryId: entry.id,
                accountId: AccountingConstants.depreciationExpenseAccountId,
                debit: calc.businessAmount,
                credit: 0,
                memo: asset.name,
                displayOrder: order
            )
            modelContext.insert(expenseLine)
            order += 1
        }

        // 借方: 事業主貸（家事使用分）
        if calc.personalAmount > 0 {
            let personalLine = PPJournalLine(
                entryId: entry.id,
                accountId: AccountingConstants.ownerDrawingsAccountId,
                debit: calc.personalAmount,
                credit: 0,
                memo: "\(asset.name) 家事使用分",
                displayOrder: order
            )
            modelContext.insert(personalLine)
            order += 1
        }

        // 貸方: 減価償却累計額
        let accumulatedLine = PPJournalLine(
            entryId: entry.id,
            accountId: AccountingConstants.accumulatedDepreciationAccountId,
            debit: 0,
            credit: calc.annualAmount,
            memo: asset.name,
            displayOrder: order
        )
        modelContext.insert(accumulatedLine)

        // バリデーション: 借方合計 == 貸方合計
        let totalDebit = calc.businessAmount + calc.personalAmount
        if totalDebit == calc.annualAmount && totalDebit > 0 {
            entry.isPosted = true
        } else {
            logger.warning("減価償却仕訳の貸借不一致: asset=\(asset.name), debit=\(totalDebit), credit=\(calc.annualAmount)")
        }

        return entry
    }

    // MARK: - Private Calculation Methods

    /// 定額法: (取得価額 - 残存) / 耐用年数、初年度月割
    private static func calculateStraightLine(
        asset: PPFixedAsset,
        fiscalYear: Int,
        acquisitionYear: Int,
        acquisitionMonth: Int,
        remainingBasis: Int
    ) -> Int {
        let annualAmount = asset.annualStraightLineAmount
        guard annualAmount > 0 else { return 0 }

        if fiscalYear == acquisitionYear {
            // 初年度: 月割計算 (取得月を含む残月数)
            let months = 13 - acquisitionMonth  // 1月取得→12ヶ月, 7月取得→6ヶ月
            return annualAmount * months / 12
        }

        return annualAmount
    }

    /// 200%定率法: 帳簿価額 × (2/耐用年数)、保証額以下で定額切替
    private static func calculateDecliningBalance(
        asset: PPFixedAsset,
        fiscalYear: Int,
        acquisitionYear: Int,
        acquisitionMonth: Int,
        bookValueBefore: Int,
        remainingBasis: Int
    ) -> Int {
        let rate = asset.decliningBalanceRate
        guard rate > 0 else { return 0 }

        // 保証額 = 取得価額 × 保証率
        let guarantee = guaranteeAmount(acquisitionCost: asset.acquisitionCost, usefulLife: asset.usefulLifeYears)

        // 定率法による償却額
        var amount = Int(Double(bookValueBefore) * rate)

        if fiscalYear == acquisitionYear {
            // 初年度月割
            let months = 13 - acquisitionMonth
            amount = amount * months / 12
        }

        // 保証額以下なら定額法に切替
        if amount < guarantee {
            // 改定償却率による定額法: 残存帳簿価額 / 残存耐用年数
            let yearsUsed = fiscalYear - acquisitionYear
            let remainingYears = max(1, asset.usefulLifeYears - yearsUsed)
            amount = remainingBasis / remainingYears
        }

        return amount
    }

    /// 少額一括 / 少額減価償却資産特例: 取得年に全額費用化
    private static func calculateImmediateExpense(
        asset: PPFixedAsset,
        fiscalYear: Int,
        acquisitionYear: Int,
        remainingBasis: Int
    ) -> Int {
        guard fiscalYear == acquisitionYear else { return 0 }
        return remainingBasis
    }

    /// 3年均等: 取得価額 / 3 を3年間（最終年は端数調整）
    private static func calculateThreeYearEqual(
        asset: PPFixedAsset,
        fiscalYear: Int,
        acquisitionYear: Int,
        remainingBasis: Int
    ) -> Int {
        let yearIndex = fiscalYear - acquisitionYear
        guard yearIndex >= 0 && yearIndex < 3 else { return 0 }
        // 3年均等: 取得価額を3で割る（残存価額は考慮しない）
        // 最終年は端数を含めた残額を計上
        if yearIndex == 2 { return remainingBasis }
        return asset.acquisitionCost / 3
    }

    /// 200%定率法の保証額を計算
    /// 耐用年数に応じた保証率テーブル（国税庁の定率法保証率）
    private static func guaranteeAmount(acquisitionCost: Int, usefulLife: Int) -> Int {
        let rate = guaranteeRate(usefulLife: usefulLife)
        return Int(Double(acquisitionCost) * rate)
    }

    /// 定率法保証率テーブル（主要な耐用年数のみ）
    private static func guaranteeRate(usefulLife: Int) -> Double {
        switch usefulLife {
        case 2: return 0.500_00
        case 3: return 0.111_11
        case 4: return 0.125_00
        case 5: return 0.108_00
        case 6: return 0.099_11
        case 7: return 0.085_61
        case 8: return 0.078_66
        case 9: return 0.069_31
        case 10: return 0.065_52
        case 15: return 0.044_48
        case 20: return 0.033_86
        default:
            // 未定義の耐用年数は概算値
            guard usefulLife > 0 else { return 0 }
            return 1.0 / Double(usefulLife * 2)
        }
    }
}
