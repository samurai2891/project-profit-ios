import SwiftData
import SwiftUI

struct FixedAssetListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showAddForm = false
    @State private var showBulkPostConfirmation = false
    @State private var reloadToken = 0
    @State private var errorMessage: String?

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var queryUseCase: FixedAssetQueryUseCase {
        FixedAssetQueryUseCase(modelContext: modelContext)
    }

    private var snapshot: FixedAssetListSnapshot {
        _ = reloadToken
        return queryUseCase.listSnapshot(currentYear: currentYear)
    }

    private var fixedAssetWorkflowUseCase: FixedAssetWorkflowUseCase {
        FixedAssetWorkflowUseCase(modelContext: modelContext)
    }

    var body: some View {
        Group {
            if snapshot.assets.isEmpty {
                emptyState
            } else {
                assetList
            }
        }
        .navigationTitle("固定資産台帳")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if !snapshot.assets.isEmpty {
                        ExportMenuButton(
                            target: .fixedAssets,
                            fiscalYear: currentYear
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
        .onAppear {
            reloadToken += 1
        }
        .onChange(of: showAddForm) { _, isPresented in
            if !isPresented {
                reloadToken += 1
            }
        }
        .alert("一括計上", isPresented: $showBulkPostConfirmation) {
            Button("計上") {
                do {
                    let count = try fixedAssetWorkflowUseCase.postAllDepreciations(fiscalYear: currentYear)
                    if count == 0 {
                        errorMessage = "計上可能な資産がありません"
                    } else {
                        reloadToken += 1
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(currentYear)年の減価償却を全資産に対して一括計上しますか？")
        }
        .alert("固定資産台帳を更新できません", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
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
            ForEach(snapshot.assets, id: \.id) { asset in
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
                let bookValue = snapshot.bookValueByAssetId[asset.id] ?? asset.acquisitionCost
                Text("帳簿: ¥\(bookValue.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: PPAssetStatus) -> some View {
        Text(status.label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: PPAssetStatus) -> Color {
        switch status {
        case .active: AppColors.success
        case .fullyDepreciated: .secondary
        case .disposed: AppColors.warning
        case .sold: AppColors.primary
        }
    }
}
