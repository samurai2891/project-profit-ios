import SwiftUI

struct InventoryInputView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: InventoryViewModel?

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(alignment: .leading, spacing: 16) {
                    yearPickerSection(viewModel: viewModel)
                    inventoryInputSection(viewModel: viewModel)
                    cogsDisplaySection(viewModel: viewModel)
                    memoSection(viewModel: viewModel)
                    saveButton(viewModel: viewModel)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("棚卸入力")
        .onAppear {
            if viewModel == nil {
                let vm = InventoryViewModel(dataStore: dataStore)
                viewModel = vm
                vm.loadForYear()
            }
        }
    }

    // MARK: - Year Picker

    private func yearPickerSection(viewModel: InventoryViewModel) -> some View {
        @Bindable var vm = viewModel
        return HStack {
            Text("年度")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("年度", selection: $vm.fiscalYear) {
                ForEach((currentYear - 5)...currentYear, id: \.self) { year in
                    Text("\(year)年").tag(year)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: viewModel.fiscalYear) {
            viewModel.loadForYear()
        }
    }

    // MARK: - Inventory Input Fields

    private func inventoryInputSection(viewModel: InventoryViewModel) -> some View {
        @Bindable var vm = viewModel
        return VStack(alignment: .leading, spacing: 12) {
            Text("棚卸データ")
                .font(.subheadline.weight(.medium))

            inventoryField(label: "期首商品棚卸高", text: $vm.openingInventoryText)
            Divider()
            inventoryField(label: "当期仕入高", text: $vm.purchasesText)
            Divider()
            inventoryField(label: "期末商品棚卸高", text: $vm.closingInventoryText)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func inventoryField(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
            Text("円")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - COGS Display

    private func cogsDisplaySection(viewModel: InventoryViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("売上原価")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(viewModel.costOfGoodsSold))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(viewModel.costOfGoodsSold >= 0 ? .primary : AppColors.error)
            }
            Spacer()
            Image(systemName: "equal.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.primary)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Memo

    private func memoSection(viewModel: InventoryViewModel) -> some View {
        @Bindable var vm = viewModel
        return VStack(alignment: .leading, spacing: 8) {
            Text("メモ")
                .font(.subheadline.weight(.medium))

            TextField("メモ（任意）", text: $vm.memo, axis: .vertical)
                .lineLimit(3...6)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Save Button

    private func saveButton(viewModel: InventoryViewModel) -> some View {
        Button {
            viewModel.save()
        } label: {
            Label(
                viewModel.existingRecord != nil ? "更新" : "保存",
                systemImage: viewModel.existingRecord != nil ? "arrow.triangle.2.circlepath" : "square.and.arrow.down"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}
