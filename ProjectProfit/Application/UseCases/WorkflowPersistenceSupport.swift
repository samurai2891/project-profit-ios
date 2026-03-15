import Foundation
import SwiftData

@MainActor
enum WorkflowPersistenceSupport {
    static func save(modelContext: ModelContext) throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func runLegacyProfileMigrationIfNeeded(modelContext: ModelContext) {
        let runner = LegacyProfileMigrationRunner(modelContext: modelContext)
        _ = runner.executeIfNeeded()
    }

    static func defaultBusinessProfile(modelContext: ModelContext) throws -> BusinessProfile? {
        let descriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).first.map(BusinessProfileEntityMapper.toDomain)
    }

    static func defaultBusinessId(modelContext: ModelContext) throws -> UUID? {
        try defaultBusinessProfile(modelContext: modelContext)?.id
    }

    static func taxYearProfile(
        modelContext: ModelContext,
        businessId: UUID,
        taxYear: Int
    ) throws -> TaxYearProfile? {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            }
        )
        return try modelContext.fetch(descriptor).first.map(TaxYearProfileEntityMapper.toDomain)
    }

    static func yearLockState(modelContext: ModelContext, year: Int) -> YearLockState {
        guard let businessId = try? defaultBusinessId(modelContext: modelContext),
              let profile = try? taxYearProfile(
                modelContext: modelContext,
                businessId: businessId,
                taxYear: year
              )
        else {
            return .open
        }
        return profile.yearLockState
    }

    static func isYearLocked(modelContext: ModelContext, year: Int) -> Bool {
        yearLockState(modelContext: modelContext, year: year) != .open
    }

    static func canPostNormalEntry(modelContext: ModelContext, year: Int) -> Bool {
        yearLockState(modelContext: modelContext, year: year).allowsNormalPosting
    }

    static func canPostAdjustingEntry(modelContext: ModelContext, year: Int) -> Bool {
        yearLockState(modelContext: modelContext, year: year).allowsAdjustingEntries
    }

    static func seedDefaultCategories(modelContext: ModelContext) throws {
        for cat in DEFAULT_CATEGORIES {
            let category = PPCategory(
                id: cat.id,
                name: cat.name,
                type: cat.type,
                icon: cat.icon,
                isDefault: true
            )
            modelContext.insert(category)
        }
        try save(modelContext: modelContext)
    }
}
