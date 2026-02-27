import SwiftUI

struct FixedAssetListView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var showAddForm = false
    @State private var showBulkPostConfirmation = false
    @State private var showSchedule = false

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        Group {
            if dataStore.fixedAssets.isEmpty {
                emptyState
            } else {
                assetList
            }
        }
        .navigationTitle("固定資産台帳")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if !dataStore.fixedAssets.isEmpty {
                        ExportMenuButton(
                            csvGenerator: {
                                CSVExportService.exportFixedAssetsCSV(
                                    assets: dataStore.fixedAssets,
                                    calculateAccumulated: { asset in
                                        dataStore.calculatePriorAccumulatedDepreciation(
                                            asset: asset, beforeYear: currentYear + 1
                                        )
                                    },
                                    calculateCurrentYear: { asset in
                                        let prior = dataStore.calculatePriorAccumulatedDepreciation(
                                            asset: asset, beforeYear: currentYear
                                        )
                                        let calc = DepreciationEngine.calculate(
                                            asset: asset,
                                            fiscalYear: currentYear,
                                            priorAccumulatedDepreciation: prior
                                        )
                                        return calc?.annualAmount ?? 0
                                    }
                                )
                            },
                            pdfGenerator: {
                                PDFExportService.exportFixedAssetsPDF(
                                    assets: dataStore.fixedAssets,
                                    fiscalYear: currentYear,
                                    calculateAccumulated: { asset in
                                        dataStore.calculatePriorAccumulatedDepreciation(
                                            asset: asset, beforeYear: currentYear + 1
                                        )
                                    },
                                    calculateCurrentYear: { asset in
                                        let prior = dataStore.calculatePriorAccumulatedDepreciation(
                                            asset: asset, beforeYear: currentYear
                                        )
                                        let calc = DepreciationEngine.calculate(
                                            asset: asset,
                                            fiscalYear: currentYear,
                                            priorAccumulatedDepreciation: prior
                                        )
                                        return calc?.annualAmount ?? 0
                                    }
                                )
                            },
                            fileNamePrefix: "固定資産台帳"
                        )
                        NavigationLink(destination: FixedAssetScheduleView()) {
                            Image(systemName: "tablecells")
                        }
                        Button {
                            showBulkPostConfirmation = true
                        } label: {
                            Image(systemName: "tray.and.arrow.down")
                        }
                    }
                    Button {
                        showAddForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddForm) {
            NavigationStack {
                FixedAssetFormView()
            }
        }
        .alert("一括計上", isPresented: $showBulkPostConfirmation) {
            Button("計上") {
                let count = dataStore.postAllDepreciations(fiscalYear: currentYear)
                if count == 0 {
                    dataStore.lastError = .invalidInput(message: "計上可能な資産がありません")
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(currentYear)年の減価償却を全資産に対して一括計上しますか？")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("固定資産がありません")
                .font(.headline)
            Text("＋ボタンから固定資産を追加してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var assetList: some View {
        List {
            ForEach(dataStore.fixedAssets, id: \.id) { asset in
                NavigationLink(destination: FixedAssetDetailView(assetId: asset.id)) {
                    assetRow(asset)
                }
            }
        }
    }

    private func assetRow(_ asset: PPFixedAsset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(asset.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                statusBadge(asset.assetStatus)
            }

            HStack {
                Text("取得: \(asset.acquisitionDate, format: .dateTime.year().month().day())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("¥\(asset.acquisitionCost.formatted())")
                    .font(.subheadline.monospacedDigit())
            }

            HStack {
                Text(asset.depreciationMethod.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let accumulated = dataStore.calculatePriorAccumulatedDepreciation(
                    asset: asset, beforeYear: currentYear + 1
                )
                let bookValue = asset.acquisitionCost - accumulated
                Text("帳簿: ¥\(bookValue.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: AssetStatus) -> some View {
        Text(status.label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: AssetStatus) -> Color {
        switch status {
        case .active: AppColors.success
        case .fullyDepreciated: .secondary
        case .disposed: AppColors.warning
        case .sold: AppColors.primary
        }
    }
}
