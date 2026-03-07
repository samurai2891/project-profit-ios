import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Scanner View

struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss

    let defaultProjectId: UUID?

    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPDFImporter = false
    @State private var showFileImporter = false
    @State private var selectedSourceType: EvidenceSourceType = .manualNoFile
    @State private var scannerService = ReceiptScannerService()
    @State private var importedPDFData: Data?
    @State private var importError: String?

    init(defaultProjectId: UUID? = nil) {
        self.defaultProjectId = defaultProjectId
    }

    var body: some View {
        NavigationStack {
            Group {
                switch scannerService.state {
                case .idle where selectedImage != nil:
                    imagePreview(selectedImage!)
                case .processing:
                    processingView
                case .completed(let output):
                    ReceiptReviewView(
                        receiptData: output.receiptData,
                        ocrText: output.ocrText,
                        receiptImage: selectedImage,
                        evidenceSourceType: selectedSourceType,
                        originalFileData: importedPDFData,
                        defaultProjectId: defaultProjectId,
                        onDismiss: { dismiss() }
                    )
                case .failed(let message):
                    errorView(message: message)
                default:
                    sourceSelectionView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView(image: $selectedImage)
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf]
            ) { result in
                handleFileImport(result: result, sourceType: .importedPDF)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .pdf]
            ) { result in
                handleFileImport(result: result, sourceType: .importedPDF)
            }
            .onChange(of: photoPickerItem) { _, newItem in
                loadPhoto(from: newItem)
            }
            .alert("読み込みエラー", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "ファイルの読み込みに失敗しました")
            }
        }
    }

    private var navigationTitle: String {
        switch scannerService.state {
        case .completed: "確認・登録"
        case .processing: "読み取り中..."
        default: "書類読取"
        }
    }

    // MARK: - Source Selection

    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.primary)
                .accessibilityHidden(true)

            Text("レシート・請求書・領収書を読み取り")
                .font(.title3.weight(.semibold))

            Text("カメラで撮影、フォトライブラリから選択、\nまたはPDF・ファイルを読み込んでください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        selectedSourceType = .camera
                        showCamera = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("カメラで撮影")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("カメラで撮影")
                    .accessibilityHint("カメラを起動して書類を撮影")
                }

                PhotosPicker(
                    selection: $photoPickerItem,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("フォトライブラリから選択")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.surface)
                    .foregroundStyle(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColors.primary, lineWidth: 1)
                    )
                }
                .accessibilityLabel("フォトライブラリから選択")
                .accessibilityHint("写真アプリから書類画像を選択")

                Button {
                    showPDFImporter = true
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                        Text("PDFを読み込む")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.surface)
                    .foregroundStyle(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColors.primary, lineWidth: 1)
                    )
                }
                .accessibilityLabel("PDFを読み込む")
                .accessibilityHint("ファイルアプリからPDF書類を選択")

                Button {
                    showFileImporter = true
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                        Text("ファイルから読み込む")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.surface)
                    .foregroundStyle(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppColors.primary, lineWidth: 1)
                    )
                }
                .accessibilityLabel("ファイルから読み込む")
                .accessibilityHint("ファイルアプリから画像またはPDFを選択")
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Image Preview

    private func imagePreview(_ image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .accessibilityLabel("選択された書類画像")

            HStack(spacing: 12) {
                Button {
                    resetSelection()
                } label: {
                    Text("やり直す")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.surface)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }
                .accessibilityLabel("やり直す")
                .accessibilityHint("画像選択に戻ります")

                Button {
                    Task { await scannerService.scan(image: image) }
                } label: {
                    HStack {
                        Image(systemName: "text.viewfinder")
                        Text("読み取り開始")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("読み取り開始")
                .accessibilityHint("書類のテキストを読み取ります")
            }
        }
        .padding(20)
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("書類を読み取り中...")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("テキスト認識と情報抽出を行っています")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("書類を読み取り中")
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)

            Text("読み取りに失敗しました")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Button {
                    resetSelection()
                } label: {
                Text("もう一度試す")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("もう一度試す")
            .accessibilityHint("画像選択に戻ってやり直します")

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Selection Reset

    private func resetSelection() {
        selectedImage = nil
        photoPickerItem = nil
        importedPDFData = nil
        selectedSourceType = .manualNoFile
        scannerService.reset()
    }

    // MARK: - Photo Loading

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        selectedSourceType = .photoLibrary
        importedPDFData = nil
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data)
            {
                selectedImage = uiImage
            }
        }
    }

    // MARK: - File Import

    private func handleFileImport(result: Result<URL, Error>, sourceType: EvidenceSourceType) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importError = "ファイルへのアクセス権限がありません"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let fileData = try Data(contentsOf: url)
                let isPDF = url.pathExtension.lowercased() == "pdf"
                    || UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true

                if isPDF {
                    guard let renderResult = PDFPageRenderer.renderFirstPage(from: fileData) else {
                        importError = "PDFの読み込みに失敗しました。有効なPDFファイルを選択してください"
                        return
                    }
                    selectedSourceType = .importedPDF
                    importedPDFData = renderResult.originalData
                    selectedImage = renderResult.image
                } else {
                    guard let uiImage = UIImage(data: fileData) else {
                        importError = "画像の読み込みに失敗しました。対応形式の画像を選択してください"
                        return
                    }
                    selectedSourceType = sourceType == .importedPDF ? .photoLibrary : sourceType
                    importedPDFData = nil
                    selectedImage = uiImage
                }
            } catch {
                importError = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
            }

        case .failure(let error):
            // User cancelled - no error to show
            if (error as NSError).code == NSUserCancelledError { return }
            importError = "ファイルの選択に失敗しました: \(error.localizedDescription)"
        }
    }
}

// MARK: - Camera View (UIImagePickerController Bridge)

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
