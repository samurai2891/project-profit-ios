import SwiftData

@MainActor
struct SettingsMaintenanceUseCase {
    private let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func deleteAllData() {
        let imagesToDelete = dataStore.transactions.compactMap(\.receiptImagePath)
            + dataStore.recurringTransactions.compactMap(\.receiptImagePath)
        let documentRecords = dataStore.listDocumentRecords()
        let documentFilesToDelete = documentRecords.map(\.storedFileName)
        let complianceLogs = dataStore.listComplianceLogs(limit: Int.max)
        let secureStoreIds = Set([dataStore.businessProfile?.id.uuidString].compactMap { $0 })

        for project in dataStore.projects {
            dataStore.modelContext.delete(project)
        }
        for transaction in dataStore.transactions {
            dataStore.modelContext.delete(transaction)
        }
        for category in dataStore.categories {
            dataStore.modelContext.delete(category)
        }
        for recurring in dataStore.recurringTransactions {
            dataStore.modelContext.delete(recurring)
        }
        for account in dataStore.accounts {
            dataStore.modelContext.delete(account)
        }
        for journalEntry in dataStore.journalEntries {
            dataStore.modelContext.delete(journalEntry)
        }
        for journalLine in dataStore.journalLines {
            dataStore.modelContext.delete(journalLine)
        }
        if let legacyProfiles = try? dataStore.modelContext.fetch(FetchDescriptor<PPAccountingProfile>()) {
            for profile in legacyProfiles {
                dataStore.modelContext.delete(profile)
            }
        }
        if let businessProfiles = try? dataStore.modelContext.fetch(FetchDescriptor<BusinessProfileEntity>()) {
            for profile in businessProfiles {
                dataStore.modelContext.delete(profile)
            }
        }
        if let taxYearProfiles = try? dataStore.modelContext.fetch(FetchDescriptor<TaxYearProfileEntity>()) {
            for profile in taxYearProfiles {
                dataStore.modelContext.delete(profile)
            }
        }
        for asset in dataStore.fixedAssets {
            dataStore.modelContext.delete(asset)
        }
        for document in documentRecords {
            dataStore.modelContext.delete(document)
        }
        for log in complianceLogs {
            dataStore.modelContext.delete(log)
        }

        if dataStore.save() {
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
            for fileName in documentFilesToDelete {
                ReceiptImageStore.deleteDocumentFile(fileName: fileName)
            }
        }

        for profileId in secureStoreIds {
            _ = ProfileSecureStore.delete(profileId: profileId)
        }

        dataStore.projects = []
        dataStore.allTransactions = []
        dataStore.categories = []
        dataStore.recurringTransactions = []
        dataStore.accounts = []
        dataStore.journalEntries = []
        dataStore.journalLines = []
        dataStore.businessProfile = nil
        dataStore.currentTaxYearProfile = nil
        dataStore.fixedAssets = []
        dataStore.seedDefaultCategories()
    }
}
