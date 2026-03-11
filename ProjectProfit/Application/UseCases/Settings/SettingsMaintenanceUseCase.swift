import SwiftData

@MainActor
struct SettingsMaintenanceUseCase {
    private let modelContext: ModelContext
    private let resetStoreState: @MainActor () -> Void

    init(
        modelContext: ModelContext,
        resetStoreState: @escaping @MainActor () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.resetStoreState = resetStoreState
    }

    func deleteAllData() {
        let imagesToDelete = transactions().compactMap(\.receiptImagePath)
            + recurringTransactions().compactMap(\.receiptImagePath)
        let documents = documentRecords()
        let documentFilesToDelete = documents.map(\.storedFileName)
        let secureStoreIds = Set(businessProfiles().map(\.id.uuidString))

        deleteAll(projects())
        deleteAll(transactions())
        deleteAll(categories())
        deleteAll(recurringTransactions())
        deleteAll(accounts())
        deleteAll(journalEntries())
        deleteAll(journalLines())
        deleteAll(legacyProfiles())
        deleteAll(businessProfileEntities())
        deleteAll(taxYearProfiles())
        deleteAll(fixedAssets())
        deleteAll(documents)
        deleteAll(complianceLogs())

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
            for fileName in documentFilesToDelete {
                ReceiptImageStore.deleteDocumentFile(fileName: fileName)
            }
            for profileId in secureStoreIds {
                _ = ProfileSecureStore.delete(profileId: profileId)
            }
            try WorkflowPersistenceSupport.seedDefaultCategories(modelContext: modelContext)
        } catch {
            modelContext.rollback()
        }

        resetStoreState()
    }

    private func deleteAll<T>(_ models: [T]) where T: PersistentModel {
        for model in models {
            modelContext.delete(model)
        }
    }

    private func projects() -> [PPProject] {
        fetch(FetchDescriptor<PPProject>())
    }

    private func transactions() -> [PPTransaction] {
        fetch(FetchDescriptor<PPTransaction>())
    }

    private func categories() -> [PPCategory] {
        fetch(FetchDescriptor<PPCategory>())
    }

    private func recurringTransactions() -> [PPRecurringTransaction] {
        fetch(FetchDescriptor<PPRecurringTransaction>())
    }

    private func accounts() -> [PPAccount] {
        fetch(FetchDescriptor<PPAccount>())
    }

    private func journalEntries() -> [PPJournalEntry] {
        fetch(FetchDescriptor<PPJournalEntry>())
    }

    private func journalLines() -> [PPJournalLine] {
        fetch(FetchDescriptor<PPJournalLine>())
    }

    private func legacyProfiles() -> [PPAccountingProfile] {
        fetch(FetchDescriptor<PPAccountingProfile>())
    }

    private func businessProfiles() -> [BusinessProfile] {
        businessProfileEntities().map(BusinessProfileEntityMapper.toDomain)
    }

    private func businessProfileEntities() -> [BusinessProfileEntity] {
        fetch(FetchDescriptor<BusinessProfileEntity>())
    }

    private func taxYearProfiles() -> [TaxYearProfileEntity] {
        fetch(FetchDescriptor<TaxYearProfileEntity>())
    }

    private func fixedAssets() -> [PPFixedAsset] {
        fetch(FetchDescriptor<PPFixedAsset>())
    }

    private func documentRecords() -> [PPDocumentRecord] {
        fetch(FetchDescriptor<PPDocumentRecord>())
    }

    private func complianceLogs() -> [PPComplianceLog] {
        fetch(FetchDescriptor<PPComplianceLog>())
    }

    private func fetch<T>(_ descriptor: FetchDescriptor<T>) -> [T] where T: PersistentModel {
        (try? modelContext.fetch(descriptor)) ?? []
    }
}
