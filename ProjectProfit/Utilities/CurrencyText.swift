import SwiftUI

/// モノスペース数字表示の共通 View。
/// 帳簿系UIで桁が揃うよう `.monospacedDigit()` を内部適用する。
struct CurrencyText: View {
    let amount: Int
    var font: Font = .subheadline
    var color: Color = .primary
    var showSign: Bool = false
    var emptyWhenZero: Bool = false

    var body: some View {
        if emptyWhenZero && amount == 0 {
            Text("")
                .font(font.monospacedDigit())
        } else {
            Text(displayText)
                .font(font.monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var displayText: String {
        if showSign && amount > 0 {
            return "+\(formatCurrency(amount))"
        }
        return formatCurrency(amount)
    }
}
