import Foundation

/// 証憑の取得元タイプ
enum EvidenceSourceType: String, Codable, Sendable, CaseIterable {
    case camera
    case photoLibrary
    case scannedPDF
    case emailAttachment
    case importedPDF
    case manualNoFile
}
