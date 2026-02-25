import SwiftUI

struct FixedAssetFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let editingAsset: PPFixedAsset?

    @State private var name: String = ""
    @State private var acquisitionDate: Date = Date()
    @State private var acquisitionCostText: String = ""
    @State private var usefulLifeYears: Int = 4
    @State private var depreciationMethod: DepreciationMethod = .straightLine
    @State private var salvageValue: Int = 1
    @State private var businessUsePercent: Int = 100
    @State private var memo: String = ""

    init(editingAsset: PPFixedAsset? = nil) {
        self.editingAsset = editingAsset
    }

    private var acquisitionCost: Int {
        Int(acquisitionCostText) ?? 0
    }

    private var isValid: Bool {
        !name.isEmpty && acquisitionCost > 0 && usefulLifeYears > 0 && businessUsePercent >= 0 && businessUsePercent <= 100
    }

    /// 金額に応じた推奨償却方法
    private var suggestedMethod: DepreciationMethod {
        let cost = acquisitionCost
        if cost < 100_000 { return .immediateExpense }
        if cost < 200_000 { return .threeYearEqual }
        if cost < 300_000 { return .smallBusiness }
        return .straightLine
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("資産名", text: $name)

                DatePicker("取得日", selection: $acquisitionDate, displayedComponents: .date)

                HStack {
                    Text("取得価額")
                    Spacer()
                    TextField("金額", text: $acquisitionCostText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("円")
                }
            }

            Section("償却設定") {
                Picker("償却方法", selection: $depreciationMethod) {
                    ForEach(DepreciationMethod.allCases, id: \.self) { method in
                        Text(method.label).tag(method)
                    }
                }

                if acquisitionCost > 0 && depreciationMethod != suggestedMethod {
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(AppColors.warning)
                        Text("¥\(acquisitionCost.formatted()) → \(suggestedMethod.label) を推奨")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if depreciationMethod == .straightLine || depreciationMethod == .decliningBalance {
                    Stepper("耐用年数: \(usefulLifeYears)年", value: $usefulLifeYears, in: 1...50)

                    HStack {
                        Text("残存価額")
                        Spacer()
                        Text("¥\(salvageValue.formatted())")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper("事業使用割合: \(businessUsePercent)%", value: $businessUsePercent, in: 0...100, step: 5)
            }

            Section("メモ") {
                TextField("メモ（任意）", text: $memo, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(editingAsset != nil ? "固定資産の編集" : "固定資産の追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveAsset()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let asset = editingAsset {
                name = asset.name
                acquisitionDate = asset.acquisitionDate
                acquisitionCostText = "\(asset.acquisitionCost)"
                usefulLifeYears = asset.usefulLifeYears
                depreciationMethod = asset.depreciationMethod
                salvageValue = asset.salvageValue
                businessUsePercent = asset.businessUsePercent
                memo = asset.memo ?? ""
            }
        }
    }

    private func saveAsset() {
        if let asset = editingAsset {
            dataStore.updateFixedAsset(
                id: asset.id,
                name: name,
                acquisitionDate: acquisitionDate,
                acquisitionCost: acquisitionCost,
                usefulLifeYears: usefulLifeYears,
                depreciationMethod: depreciationMethod,
                salvageValue: salvageValue,
                businessUsePercent: businessUsePercent,
                memo: memo.isEmpty ? nil : memo
            )
        } else {
            dataStore.addFixedAsset(
                name: name,
                acquisitionDate: acquisitionDate,
                acquisitionCost: acquisitionCost,
                usefulLifeYears: usefulLifeYears,
                depreciationMethod: depreciationMethod,
                salvageValue: salvageValue,
                businessUsePercent: businessUsePercent,
                memo: memo.isEmpty ? nil : memo
            )
        }
    }
}
