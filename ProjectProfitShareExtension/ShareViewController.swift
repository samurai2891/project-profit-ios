import Foundation
import UIKit
import UniformTypeIdentifiers

private struct SharedImportQueueRecord: Codable {
    let id: UUID
    let originalFilename: String
    let storedFilename: String
    let typeIdentifier: String
    let createdAt: Date
}

private enum ShareImportError: LocalizedError {
    case unsupportedType
    case appGroupUnavailable
    case invalidSharedDefaults
    case noInputItem
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "画像またはPDFファイルのみ取り込めます。"
        case .appGroupUnavailable:
            return "共有保存先の初期化に失敗しました。"
        case .invalidSharedDefaults:
            return "共有キューの保存に失敗しました。"
        case .noInputItem:
            return "共有データを取得できませんでした。"
        case .loadFailed(let message):
            return message
        }
    }
}

final class ShareViewController: UIViewController {
    private static let appGroupIdentifier = "group.com.projectprofit.ProjectProfit"
    private static let queueDefaultsKey = "shareImportQueue.v1"
    private static let inboxDirectoryName = "ShareInbox"

    private let indicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private var hasStarted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await importAttachment()
        }
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = "共有ファイルを取り込み中..."

        view.addSubview(indicator)
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            messageLabel.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func showResultMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.indicator.stopAnimating()
            self?.messageLabel.text = message
        }
    }

    private func completeRequest(after delay: TimeInterval = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func importAttachment() async {
        do {
            guard let provider = firstSupportedProvider() else {
                throw ShareImportError.noInputItem
            }
            let imported = try await importRecord(from: provider)
            try appendToQueue(imported)
            showResultMessage("取り込みキューに追加しました。アプリを開いて確認してください。")
            completeRequest()
        } catch {
            showResultMessage(error.localizedDescription)
            completeRequest(after: 1.0)
        }
    }

    private func firstSupportedProvider() -> NSItemProvider? {
        let extensionItems = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in extensionItems {
            let attachments = item.attachments ?? []
            if let provider = attachments.first(where: { preferredTypeIdentifier(for: $0) != nil }) {
                return provider
            }
        }
        return nil
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return UTType.pdf.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return UTType.image.identifier
        }
        return nil
    }

    private func importRecord(from provider: NSItemProvider) async throws -> SharedImportQueueRecord {
        guard let typeIdentifier = preferredTypeIdentifier(for: provider) else {
            throw ShareImportError.unsupportedType
        }

        guard let inboxDirectory = sharedInboxDirectoryURL() else {
            throw ShareImportError.appGroupUnavailable
        }

        let originalName: String
        let storedFileName: String
        let destinationURL: URL

        if let sourceURL = try await loadFileURL(from: provider, typeIdentifier: typeIdentifier) {
            let fileExtension = normalizedFileExtension(
                pathExtension: sourceURL.pathExtension,
                typeIdentifier: typeIdentifier
            )
            storedFileName = "\(UUID().uuidString).\(fileExtension)"
            destinationURL = inboxDirectory.appendingPathComponent(storedFileName)
            originalName = sourceURL.lastPathComponent
            try replaceItem(at: destinationURL, with: sourceURL)
        } else {
            let data = try await loadFileData(from: provider, typeIdentifier: typeIdentifier)
            let fileExtension = normalizedFileExtension(
                pathExtension: "",
                typeIdentifier: typeIdentifier
            )
            storedFileName = "\(UUID().uuidString).\(fileExtension)"
            destinationURL = inboxDirectory.appendingPathComponent(storedFileName)
            originalName = "shared.\(fileExtension)"
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try data.write(to: destinationURL, options: .atomic)
        }

        return SharedImportQueueRecord(
            id: UUID(),
            originalFilename: originalName,
            storedFilename: storedFileName,
            typeIdentifier: typeIdentifier,
            createdAt: Date()
        )
    }

    private func loadFileURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    let nsError = error as NSError
                    // Some providers do not expose file representation for images; fallback to data representation.
                    if nsError.domain == NSItemProvider.errorDomain {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: ShareImportError.loadFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    private func loadFileData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: ShareImportError.loadFailed(error.localizedDescription))
                    return
                }
                guard let data else {
                    continuation.resume(throwing: ShareImportError.noInputItem)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func appendToQueue(_ record: SharedImportQueueRecord) throws {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            throw ShareImportError.invalidSharedDefaults
        }

        let existing: [SharedImportQueueRecord]
        if let data = defaults.data(forKey: Self.queueDefaultsKey) {
            existing = (try? JSONDecoder().decode([SharedImportQueueRecord].self, from: data)) ?? []
        } else {
            existing = []
        }

        let updated = existing + [record]
        let encoded = try JSONEncoder().encode(updated)
        defaults.set(encoded, forKey: Self.queueDefaultsKey)
    }

    private func sharedInboxDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            return nil
        }

        let inboxURL = containerURL.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: inboxURL.path) {
            do {
                try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return inboxURL
    }

    private func normalizedFileExtension(pathExtension: String, typeIdentifier: String) -> String {
        if !pathExtension.isEmpty {
            return pathExtension.lowercased()
        }
        if let utType = UTType(typeIdentifier), let preferredExtension = utType.preferredFilenameExtension {
            return preferredExtension.lowercased()
        }
        return typeIdentifier == UTType.pdf.identifier ? "pdf" : "jpg"
    }

    private func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}
