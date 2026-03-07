import Foundation

/// 取引先の源泉徴収に関する支払先情報
/// 支払調書（法定調書）の作成に必要な属性を保持する
struct PayeeInfo: Codable, Sendable, Equatable, Hashable {
    /// 源泉徴収の対象となる支払先かどうか
    let isWithholdingSubject: Bool
    /// 源泉徴収の区分（対象でない場合は nil）
    let withholdingCategory: WithholdingTaxCode?

    init(
        isWithholdingSubject: Bool = false,
        withholdingCategory: WithholdingTaxCode? = nil
    ) {
        self.isWithholdingSubject = isWithholdingSubject
        self.withholdingCategory = withholdingCategory
    }

    /// イミュータブル更新
    func updated(
        isWithholdingSubject: Bool? = nil,
        withholdingCategory: WithholdingTaxCode?? = nil
    ) -> PayeeInfo {
        PayeeInfo(
            isWithholdingSubject: isWithholdingSubject ?? self.isWithholdingSubject,
            withholdingCategory: withholdingCategory ?? self.withholdingCategory
        )
    }
}
