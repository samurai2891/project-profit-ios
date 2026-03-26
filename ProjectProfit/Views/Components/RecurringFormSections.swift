import PhotosUI
import SwiftUI

// MARK: - Recurring Receipt Image Section

/// 定期取引フォーム用の添付画像セクション（RecurringFormViewから抽出）
struct RecurringReceiptImageSection: View {
    let recurring: PPRecurringTransaction?
    @Binding var selectedImage: UIImage?
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var showCamera: Bool
    @Binding var showReceiptPreview: Bool
    @Binding var showRemoveImageAlert: Bool
    let imageRemoved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添付画像")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = selectedImage {
                receiptImagePreviewRow(image: image)
            } else if !imageRemoved,
                      let r = recurring,
                      let imagePath = r.receiptImagePath,
                      let existingImage = ReceiptImageStore.loadImage(fileName: imagePath) {
                receiptImagePreviewRow(image: existingImage)
            } else {
                imagePickerButtons
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func receiptImagePreviewRow(image: UIImage) -> some View {
        VStack(spacing: 8) {
            Button {
                showReceiptPreview = true
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("添付画像を表示")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添付画像を表示")

            HStack(spacing: 12) {
                Button {
                    showRemoveImageAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("削除")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.error)
                }
                .accessibilityLabel("添付画像を削除")

                Spacer()

                imagePickerButtons
            }
        }
    }

    @ViewBuilder
    private var imagePickerButtons: some View {
        HStack(spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                        Text("撮影")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("カメラで撮影")
            }

            PhotosPicker(
                selection: $photoPickerItem,
                matching: .images
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                    Text("選択")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("フォトライブラリから選択")
        }
    }
}

// MARK: - Recurring Project Allocation Section

/// 定期取引フォーム用のプロジェクト配分セクション（RecurringFormViewから抽出）
struct RecurringProjectAllocationSection: View {
    let projects: [PPProject]
    @Binding var allocations: [(id: UUID, projectId: UUID, ratio: Int)]

    private var projectNamesById: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    private var totalRatio: Int {
        allocations.reduce(0) { $0 + $1.ratio }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("プロジェクト配分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("合計: \(totalRatio)%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(totalRatio == 100 ? AppColors.success : AppColors.error)
            }

            if projects.isEmpty {
                Text("プロジェクトがありません")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.muted)
            } else {
                ForEach(Array(allocations.enumerated()), id: \.element.id) { index, alloc in
                    allocationRow(index: index, alloc: alloc)
                }

                addProjectButton
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func allocationRow(index: Int, alloc: (id: UUID, projectId: UUID, ratio: Int)) -> some View {
        let projectName = projectNamesById[alloc.projectId] ?? "選択"
        return HStack {
            Menu {
                let usedIds = Set(allocations.map(\.projectId))
                ForEach(projects.filter { !usedIds.contains($0.id) || $0.id == alloc.projectId }, id: \.id) { project in
                    Button(project.name) {
                        var updated = allocations
                        updated[index] = (id: alloc.id, projectId: project.id, ratio: alloc.ratio)
                        allocations = updated
                    }
                }
            } label: {
                Text(projectName)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.primary.opacity(0.1))
                    .foregroundStyle(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("0", text: Binding(
                    get: { String(allocations[index].ratio) },
                    set: { newValue in
                        let clamped = min(100, max(0, Int(newValue) ?? 0))
                        var updated = allocations
                        updated[index] = (id: alloc.id, projectId: alloc.projectId, ratio: clamped)
                        allocations = updated
                    }
                ))
                .keyboardType(.numberPad)
                .frame(width: 50)
                .multilineTextAlignment(.center)
                .padding(6)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))

                Text("%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if allocations.count > 1 {
                Button {
                    allocations = allocations.filter { $0.id != alloc.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.error)
                }
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var addProjectButton: some View {
        if projects.count > allocations.count {
            Button {
                let usedIds = Set(allocations.map(\.projectId))
                if let available = projects.first(where: { !usedIds.contains($0.id) }) {
                    allocations = allocations + [(id: UUID(), projectId: available.id, ratio: 0)]
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("プロジェクトを追加（按分）")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.primary)
                .frame(maxWidth: .infinity)
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
                )
            }
        }
    }
}
