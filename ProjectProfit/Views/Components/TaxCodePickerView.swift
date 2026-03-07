import SwiftUI

struct TaxCodePickerView: View {
    @Binding var selectedTaxCode: TaxCode?

    var body: some View {
        HStack {
            Text("税区分")
                .font(.subheadline)
            Spacer()
            Picker("税区分", selection: $selectedTaxCode) {
                Text("未設定").tag(TaxCode?.none)
                ForEach(TaxCode.allCases, id: \.self) { code in
                    Text(code.displayName).tag(TaxCode?.some(code))
                }
            }
            .pickerStyle(.menu)
        }
    }
}
