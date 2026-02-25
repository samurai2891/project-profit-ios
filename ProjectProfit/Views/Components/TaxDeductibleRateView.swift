import SwiftUI

/// 経費按分率（家事按分）スライダー
struct TaxDeductibleRateView: View {
    @Binding var rate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("経費按分率")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(rate)%")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(rate == 100 ? AppColors.success : AppColors.warning)
            }

            Slider(
                value: Binding(
                    get: { Double(rate) },
                    set: { rate = Int($0) }
                ),
                in: 0...100,
                step: 5
            )
            .tint(AppColors.primary)
            .accessibilityLabel("経費按分率")
            .accessibilityValue("\(rate)%")

            HStack {
                Text("事業用: \(rate)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("個人用: \(100 - rate)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if rate < 100 {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("個人使用分(\(100 - rate)%)は事業主貸として処理されます")
                        .font(.caption2)
                }
                .foregroundStyle(AppColors.warning)
            }
        }
    }
}
