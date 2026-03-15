import SwiftData
import SwiftUI

struct UnclassifiedTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
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
                viewModel = ClassificationViewModel(modelContext: modelContext)
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
                Text("要レビュー")
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
            Text("要レビュー候補")
                .font(.subheadline.weight(.medium))

            if viewModel.unclassifiedResults.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                    Text("レビュー待ちの分類候補はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(20)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(viewModel.unclassifiedResults, id: \.candidate.id) { item in
                    unclassifiedRow(
                        item: item,
                        result: item.result,
                        viewModel: viewModel
                    )
                }
            }
        }
    }

    private func confidenceBadge(confidence: Double) -> some View {
        let color: Color
        if confidence >= ClassificationEngine.highConfidenceThreshold {
            color = AppColors.success
        } else if confidence >= ClassificationEngine.lowConfidenceThreshold {
            color = AppColors.warning
        } else {
            color = AppColors.error
        }
        let percent = Int(confidence * 100)
        return Text("\(percent)%")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func unclassifiedRow(
        item: ClassificationResultItem,
        result: ClassificationEngine.ClassificationResult,
        viewModel: ClassificationViewModel
    ) -> some View {
        let candidate = item.candidate
        let evidence = item.evidence
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatDate(evidence?.issueDate ?? candidate.candidateDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(NSDecimalNumber(decimal: displayAmount(candidate)).intValue))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }

            Text(primaryTitle(candidate: candidate, evidence: evidence))
                .font(.subheadline)
                .lineLimit(1)

            Text(secondaryTitle(candidate: candidate, evidence: evidence))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(result.taxLine.label)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppColors.warning)
                    .clipShape(Capsule())

                // Confidence badge
                confidenceBadge(confidence: result.confidence)

                if result.needsReview {
                    Text("要確認")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.error)
                        .clipShape(Capsule())
                }

                Text(categoryLabel(for: item.suggestedCategoryId))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    ForEach(TaxLine.allCases) { taxLine in
                        Button(taxLine.label) {
                            viewModel.correctClassification(
                                candidateId: candidate.id,
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

    private func primaryTitle(candidate: PostingCandidate, evidence: EvidenceDocument?) -> String {
        let title = candidate.memo
            ?? candidate.legacySnapshot?.counterpartyName
            ?? evidence?.structuredFields?.counterpartyName
            ?? evidence?.originalFilename
            ?? ""
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "（摘要なし）" : normalized
    }

    private func secondaryTitle(candidate: PostingCandidate, evidence: EvidenceDocument?) -> String {
        let parts: [String] = [
            candidate.source.displayName,
            evidence?.legalDocumentType.displayName,
            evidence?.structuredFields?.counterpartyName
        ].compactMap { rawValue in
            guard let value = rawValue, !value.isEmpty else {
                return nil
            }
            return value
        }
        return parts.isEmpty ? "分類候補" : parts.joined(separator: " / ")
    }

    private func displayAmount(_ candidate: PostingCandidate) -> Decimal {
        let debitTotal = candidate.proposedLines
            .filter { $0.debitAccountId != nil }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let creditTotal = candidate.proposedLines
            .filter { $0.creditAccountId != nil }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return max(debitTotal, creditTotal)
    }

    private func categoryLabel(for categoryId: String) -> String {
        guard !categoryId.isEmpty else {
            return "カテゴリ未解決"
        }
        return "候補カテゴリ: \(categoryId)"
    }
}
