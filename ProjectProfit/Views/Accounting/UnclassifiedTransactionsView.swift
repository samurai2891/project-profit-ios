import SwiftUI

struct UnclassifiedTransactionsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: ClassificationViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("自動分類")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = ClassificationViewModel(dataStore: dataStore)
            }
        }
    }

    private func content(viewModel: ClassificationViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard(viewModel: viewModel)
                unclassifiedSection(viewModel: viewModel)
            }
            .padding(16)
        }
        .onAppear { viewModel.refresh() }
    }

    private func summaryCard(viewModel: ClassificationViewModel) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("分類済")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.classifiedCount)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColors.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("未分類")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.unclassifiedResults.count)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(viewModel.unclassifiedResults.isEmpty ? .secondary : AppColors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func unclassifiedSection(viewModel: ClassificationViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("未分類の取引")
                .font(.subheadline.weight(.medium))

            if viewModel.unclassifiedResults.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                    Text("すべての取引が分類されています")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(20)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(viewModel.unclassifiedResults, id: \.transaction.id) { item in
                    unclassifiedRow(
                        transaction: item.transaction,
                        result: item.result,
                        viewModel: viewModel
                    )
                }
            }
        }
    }

    private func unclassifiedRow(
        transaction: PPTransaction,
        result: ClassificationEngine.ClassificationResult,
        viewModel: ClassificationViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatDate(transaction.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(transaction.amount))
                    .font(.subheadline.weight(.medium))
            }

            Text(transaction.memo.isEmpty ? "（メモなし）" : transaction.memo)
                .font(.subheadline)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(result.taxLine.label)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppColors.warning)
                    .clipShape(Capsule())

                Spacer()

                // Phase 9B: 分類修正メニュー
                Menu {
                    ForEach(TaxLine.allCases) { taxLine in
                        Button(taxLine.label) {
                            viewModel.correctClassification(
                                transactionId: transaction.id,
                                newTaxLine: taxLine
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil.circle")
                        Text("分類を修正")
                    }
                    .font(.caption)
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
