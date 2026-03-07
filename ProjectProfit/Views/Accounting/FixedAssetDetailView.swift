import SwiftUI

struct FixedAssetDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let assetId: UUID

    @State private var showEditForm = false
    @State private var showDeleteConfirmation = false
    @State private var showPostConfirmation = false
    @State private var showDisposeConfirmation = false

    private var asset: PPFixedAsset? {
        dataStore.fixedAssets.first { $0.id == assetId }
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var isAssetFiscalYearLocked: Bool {
        guard let asset else { return false }
        let year = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        return dataStore.isYearLocked(year)
    }

    private var isCurrentYearLocked: Bool {
        dataStore.isYearLocked(currentYear)
    }

    private var schedule: [DepreciationCalculation] {
        guard let asset else { return [] }
        return dataStore.previewDepreciationSchedule(asset: asset)
    }

    private var relatedEntries: [PPJournalEntry] {
        guard let asset else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        return (acquisitionYear...currentYear).compactMap { year in
            let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: assetId, year: year)
            return dataStore.journalEntries.first { $0.sourceKey == sourceKey }
        }
    }

    var body: some View {
        Group {
            if let asset {
                assetContent(asset)
            } else {
                Text("固定資産が見つかりません")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("固定資産詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let currentAsset = asset {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEditForm = true
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        .disabled(isAssetFiscalYearLocked)
                        Button {
                            showPostConfirmation = true
                        } label: {
                            Label("\(currentYear)年の償却を計上", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(isCurrentYearLocked)
                        if currentAsset.assetStatus == .active {
                            Button(role: .destructive) {
                                showDisposeConfirmation = true
                            } label: {
                                Label("除却", systemImage: "xmark.circle")
                            }
                            .disabled(isAssetFiscalYearLocked)
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .disabled(isAssetFiscalYearLocked)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditForm) {
            NavigationStack {
                FixedAssetFormView(editingAsset: asset)
            }
        }
        .alert("固定資産を削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("削除", role: .destructive) {
                if dataStore.deleteFixedAsset(id: assetId) {
                    dismiss()
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この資産と関連する減価償却仕訳がすべて削除されます。")
        }
        .alert("減価償却を計上しますか？", isPresented: $showPostConfirmation) {
            Button("計上") {
                dataStore.postDepreciation(assetId: assetId, fiscalYear: currentYear)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(currentYear)年の減価償却を計上します。")
        }
        .alert("この資産を除却しますか？", isPresented: $showDisposeConfirmation) {
            Button("除却", role: .destructive) {
                dataStore.updateFixedAsset(
                    id: assetId,
                    assetStatus: .disposed,
                    disposalDate: .some(Date())
                )
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("資産のステータスを「除却済み」に変更します。")
        }
    }

    // MARK: - Content

    private func assetContent(_ asset: PPFixedAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoSection(asset)
                scheduleSection
                if !relatedEntries.isEmpty {
                    entriesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Info Section

    private func infoSection(_ asset: PPFixedAsset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("資産情報")
                .font(.subheadline.weight(.medium))

            infoRow("資産名", asset.name)
            infoRow("取得日", asset.acquisitionDate.formatted(.dateTime.year().month().day()))
            infoRow("取得価額", "¥\(asset.acquisitionCost.formatted())")
            infoRow("償却方法", asset.depreciationMethod.label)
            if asset.depreciationMethod == .straightLine || asset.depreciationMethod == .decliningBalance {
                infoRow("耐用年数", "\(asset.usefulLifeYears)年")
                infoRow("残存価額", "¥\(asset.salvageValue.formatted())")
            }
            infoRow("事業使用割合", "\(asset.businessUsePercent)%")
            infoRow("ステータス", asset.assetStatus.label)
            if isAssetFiscalYearLocked {
                Label("取得年度がロック済みのため編集・削除はできません", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }
            if let memo = asset.memo, !memo.isEmpty {
                infoRow("メモ", memo)
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("償却スケジュール")
                .font(.subheadline.weight(.medium))

            if schedule.isEmpty {
                Text("償却スケジュールなし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(schedule) { calc in
                    HStack {
                        Text("\(calc.fiscalYear)年")
                            .font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("償却: ¥\(calc.annualAmount.formatted())")
                                .font(.caption.monospacedDigit())
                            Text("帳簿: ¥\(calc.bookValueAfter.formatted())")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    if calc.id != schedule.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Entries Section

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("計上済み仕訳")
                .font(.subheadline.weight(.medium))

            ForEach(relatedEntries, id: \.id) { entry in
                HStack {
                    Text(entry.date, format: .dateTime.year().month().day())
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: entry.isPosted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.isPosted ? AppColors.success : .secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
