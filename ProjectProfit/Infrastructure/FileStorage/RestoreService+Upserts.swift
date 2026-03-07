import Foundation
import SwiftData

extension RestoreService {
    func upsertLegacyProjects(_ snapshots: [LegacyProjectSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPProject>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = snapshot.name
                existing.projectDescription = snapshot.projectDescription
                existing.status = snapshot.status
                existing.startDate = snapshot.startDate
                existing.completedAt = snapshot.completedAt
                existing.plannedEndDate = snapshot.plannedEndDate
                existing.isArchived = snapshot.isArchived
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyCategories(_ snapshots: [LegacyCategorySnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPCategory>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = snapshot.name
                existing.type = snapshot.type
                existing.icon = snapshot.icon
                existing.isDefault = snapshot.isDefault
                existing.linkedAccountId = snapshot.linkedAccountId
                existing.archivedAt = snapshot.archivedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyRecurringTransactions(_ snapshots: [LegacyRecurringTransactionSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPRecurringTransaction>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = snapshot.name
                existing.type = snapshot.type
                existing.amount = snapshot.amount
                existing.categoryId = snapshot.categoryId
                existing.memo = snapshot.memo
                existing.allocationMode = snapshot.allocationMode
                existing.allocations = snapshot.allocations
                existing.frequency = snapshot.frequency
                existing.dayOfMonth = snapshot.dayOfMonth
                existing.monthOfYear = snapshot.monthOfYear
                existing.isActive = snapshot.isActive
                existing.endDate = snapshot.endDate
                existing.lastGeneratedDate = snapshot.lastGeneratedDate
                existing.skipDates = snapshot.skipDates
                existing.yearlyAmortizationMode = snapshot.yearlyAmortizationMode
                existing.lastGeneratedMonths = snapshot.lastGeneratedMonths
                existing.notificationTiming = snapshot.notificationTiming
                existing.receiptImagePath = snapshot.receiptImagePath
                existing.paymentAccountId = snapshot.paymentAccountId
                existing.transferToAccountId = snapshot.transferToAccountId
                existing.taxDeductibleRate = snapshot.taxDeductibleRate
                existing.counterpartyId = snapshot.counterpartyId
                existing.counterparty = snapshot.counterparty
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyTransactions(_ snapshots: [LegacyTransactionSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPTransaction>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.type = snapshot.type
                existing.amount = snapshot.amount
                existing.date = snapshot.date
                existing.categoryId = snapshot.categoryId
                existing.memo = snapshot.memo
                existing.allocations = snapshot.allocations
                existing.recurringId = snapshot.recurringId
                existing.receiptImagePath = snapshot.receiptImagePath
                existing.lineItems = snapshot.lineItems
                existing.isManuallyEdited = snapshot.isManuallyEdited
                existing.paymentAccountId = snapshot.paymentAccountId
                existing.transferToAccountId = snapshot.transferToAccountId
                existing.taxDeductibleRate = snapshot.taxDeductibleRate
                existing.bookkeepingMode = snapshot.bookkeepingMode
                existing.journalEntryId = snapshot.journalEntryId
                existing.taxAmount = snapshot.taxAmount
                existing.taxRate = snapshot.taxRate
                existing.isTaxIncluded = snapshot.isTaxIncluded
                existing.taxCategory = snapshot.taxCategory
                existing.counterpartyId = snapshot.counterpartyId
                existing.counterparty = snapshot.counterparty
                existing.deletedAt = snapshot.deletedAt
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyAccounts(_ snapshots: [LegacyAccountSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPAccount>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.code = snapshot.code
                existing.name = snapshot.name
                existing.accountType = snapshot.accountType
                existing.normalBalance = snapshot.normalBalance
                existing.subtype = snapshot.subtype
                existing.parentAccountId = snapshot.parentAccountId
                existing.isSystem = snapshot.isSystem
                existing.isActive = snapshot.isActive
                existing.displayOrder = snapshot.displayOrder
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyJournalEntries(_ snapshots: [LegacyJournalEntrySnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPJournalEntry>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.sourceKey = snapshot.sourceKey
                existing.date = snapshot.date
                existing.entryType = snapshot.entryType
                existing.memo = snapshot.memo
                existing.isPosted = snapshot.isPosted
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyJournalLines(_ snapshots: [LegacyJournalLineSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPJournalLine>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.entryId = snapshot.entryId
                existing.accountId = snapshot.accountId
                existing.debit = snapshot.debit
                existing.credit = snapshot.credit
                existing.memo = snapshot.memo
                existing.displayOrder = snapshot.displayOrder
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyAccountingProfiles(_ snapshots: [LegacyAccountingProfileSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPAccountingProfile>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.fiscalYear = snapshot.fiscalYear
                existing.bookkeepingMode = snapshot.bookkeepingMode
                existing.businessName = snapshot.businessName
                existing.ownerName = snapshot.ownerName
                existing.taxOfficeCode = snapshot.taxOfficeCode
                existing.isBlueReturn = snapshot.isBlueReturn
                existing.defaultPaymentAccountId = snapshot.defaultPaymentAccountId
                existing.openingDate = snapshot.openingDate
                existing.lockedAt = snapshot.lockedAt
                existing.lockedYears = snapshot.lockedYears
                existing.ownerNameKana = snapshot.ownerNameKana
                existing.postalCode = snapshot.postalCode
                existing.address = snapshot.address
                existing.phoneNumber = snapshot.phoneNumber
                existing.dateOfBirth = snapshot.dateOfBirth
                existing.businessCategory = snapshot.businessCategory
                existing.myNumberFlag = snapshot.myNumberFlag
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyUserRules(_ snapshots: [LegacyUserRuleSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPUserRule>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.keyword = snapshot.keyword
                existing.taxLine = snapshot.taxLine
                existing.priority = snapshot.priority
                existing.isActive = snapshot.isActive
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyFixedAssets(_ snapshots: [LegacyFixedAssetSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPFixedAsset>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = snapshot.name
                existing.acquisitionDate = snapshot.acquisitionDate
                existing.acquisitionCost = snapshot.acquisitionCost
                existing.usefulLifeYears = snapshot.usefulLifeYears
                existing.depreciationMethod = snapshot.depreciationMethod
                existing.salvageValue = snapshot.salvageValue
                existing.assetStatus = snapshot.assetStatus
                existing.disposalDate = snapshot.disposalDate
                existing.disposalAmount = snapshot.disposalAmount
                existing.memo = snapshot.memo
                existing.businessUsePercent = snapshot.businessUsePercent
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyInventory(_ snapshots: [LegacyInventoryRecordSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPInventoryRecord>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.fiscalYear = snapshot.fiscalYear
                existing.openingInventory = snapshot.openingInventory
                existing.purchases = snapshot.purchases
                existing.closingInventory = snapshot.closingInventory
                existing.memo = snapshot.memo
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyDocuments(_ snapshots: [LegacyDocumentRecordSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPDocumentRecord>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.transactionId = snapshot.transactionId
                existing.documentType = snapshot.documentType
                existing.retentionCategory = snapshot.retentionCategory
                existing.retentionYears = snapshot.retentionYears
                existing.storedFileName = snapshot.storedFileName
                existing.originalFileName = snapshot.originalFileName
                existing.mimeType = snapshot.mimeType
                existing.fileSize = snapshot.fileSize
                existing.contentHash = snapshot.contentHash
                existing.issueDate = snapshot.issueDate
                existing.note = snapshot.note
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyComplianceLogs(_ snapshots: [LegacyComplianceLogSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPComplianceLog>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.eventType = snapshot.eventType
                existing.message = snapshot.message
                existing.documentId = snapshot.documentId
                existing.transactionId = snapshot.transactionId
                existing.createdAt = snapshot.createdAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLegacyTransactionLogs(_ snapshots: [LegacyTransactionLogSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<PPTransactionLog>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.transactionId = snapshot.transactionId
                existing.fieldName = snapshot.fieldName
                existing.oldValue = snapshot.oldValue
                existing.newValue = snapshot.newValue
                existing.changedAt = snapshot.changedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLedgerBooks(_ snapshots: [LegacyLedgerBookSnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<SDLedgerBook>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.ledgerTypeRaw = snapshot.ledgerTypeRaw
                existing.title = snapshot.title
                existing.metadataJSON = snapshot.metadataJSON
                existing.includeInvoice = snapshot.includeInvoice
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertLedgerEntries(_ snapshots: [LegacyLedgerEntrySnapshot]) throws {
        for snapshot in snapshots {
            let descriptor = FetchDescriptor<SDLedgerEntry>(predicate: #Predicate { $0.id == snapshot.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.bookId = snapshot.bookId
                existing.entryJSON = snapshot.entryJSON
                existing.sortOrder = snapshot.sortOrder
                existing.createdAt = snapshot.createdAt
                existing.updatedAt = snapshot.updatedAt
            } else {
                modelContext.insert(snapshot.toModel())
            }
        }
    }

    func upsertBusinessProfiles(_ profiles: [BusinessProfile]) throws {
        for profile in profiles {
            let descriptor = FetchDescriptor<BusinessProfileEntity>(predicate: #Predicate { $0.businessId == profile.id })
            if let existing = try modelContext.fetch(descriptor).first {
                BusinessProfileEntityMapper.update(existing, from: profile)
                existing.createdAt = profile.createdAt
            } else {
                modelContext.insert(BusinessProfileEntityMapper.toEntity(profile))
            }
        }
    }

    func upsertTaxYearProfiles(_ profiles: [TaxYearProfile]) throws {
        for profile in profiles {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(predicate: #Predicate { $0.profileId == profile.id })
            if let existing = try modelContext.fetch(descriptor).first {
                TaxYearProfileEntityMapper.update(existing, from: profile)
                existing.createdAt = profile.createdAt
            } else {
                modelContext.insert(TaxYearProfileEntityMapper.toEntity(profile))
            }
        }
    }

    func upsertEvidenceDocuments(_ evidenceDocuments: [EvidenceDocument]) throws {
        for evidence in evidenceDocuments {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(predicate: #Predicate { $0.evidenceId == evidence.id })
            if let existing = try modelContext.fetch(descriptor).first {
                EvidenceRecordEntityMapper.update(existing, from: evidence)
                existing.createdAt = evidence.createdAt
            } else {
                modelContext.insert(EvidenceRecordEntityMapper.toEntity(evidence))
            }
        }
    }

    func upsertPostingCandidates(_ candidates: [PostingCandidate]) throws {
        for candidate in candidates {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(predicate: #Predicate { $0.candidateId == candidate.id })
            if let existing = try modelContext.fetch(descriptor).first {
                PostingCandidateEntityMapper.update(existing, from: candidate)
                existing.createdAt = candidate.createdAt
            } else {
                modelContext.insert(PostingCandidateEntityMapper.toEntity(candidate))
            }
        }
    }

    func upsertCanonicalJournals(_ journals: [CanonicalJournalEntry]) throws {
        for journal in journals {
            let descriptor = FetchDescriptor<JournalEntryEntity>(predicate: #Predicate { $0.journalId == journal.id })
            if let existing = try modelContext.fetch(descriptor).first {
                let previousLines = existing.lines
                CanonicalJournalEntryEntityMapper.update(existing, from: journal)
                existing.lines = []
                previousLines.forEach(modelContext.delete)
                existing.lines = CanonicalJournalEntryEntityMapper.makeLineEntities(from: journal.lines, journalEntry: existing)
                existing.createdAt = journal.createdAt
            } else {
                modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(journal))
            }
        }
    }

    func upsertCounterparties(_ counterparties: [Counterparty]) throws {
        for counterparty in counterparties {
            let descriptor = FetchDescriptor<CounterpartyEntity>(predicate: #Predicate { $0.counterpartyId == counterparty.id })
            if let existing = try modelContext.fetch(descriptor).first {
                CounterpartyEntityMapper.update(existing, from: counterparty)
                existing.createdAt = counterparty.createdAt
            } else {
                modelContext.insert(CounterpartyEntityMapper.toEntity(counterparty))
            }
        }
    }

    func upsertCanonicalAccounts(_ accounts: [CanonicalAccount]) throws {
        for account in accounts {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(predicate: #Predicate { $0.accountId == account.id })
            if let existing = try modelContext.fetch(descriptor).first {
                CanonicalAccountEntityMapper.update(existing, from: account)
                existing.createdAt = account.createdAt
            } else {
                modelContext.insert(CanonicalAccountEntityMapper.toEntity(account))
            }
        }
    }

    func upsertDistributionRules(_ rules: [DistributionRule]) throws {
        for rule in rules {
            let descriptor = FetchDescriptor<DistributionRuleEntity>(predicate: #Predicate { $0.ruleId == rule.id })
            if let existing = try modelContext.fetch(descriptor).first {
                DistributionRuleEntityMapper.update(existing, from: rule)
                existing.createdAt = rule.createdAt
            } else {
                modelContext.insert(DistributionRuleEntityMapper.toEntity(rule))
            }
        }
    }

    func upsertAuditEvents(_ events: [AuditEvent]) throws {
        for event in events {
            let descriptor = FetchDescriptor<AuditEventEntity>(predicate: #Predicate { $0.eventId == event.id })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.businessId = event.businessId
                existing.eventTypeRaw = event.eventType.rawValue
                existing.aggregateType = event.aggregateType
                existing.aggregateId = event.aggregateId
                existing.beforeStateHash = event.beforeStateHash
                existing.afterStateHash = event.afterStateHash
                existing.actor = event.actor
                existing.createdAt = event.createdAt
                existing.reason = event.reason
                existing.relatedEvidenceId = event.relatedEvidenceId
                existing.relatedJournalId = event.relatedJournalId
            } else {
                modelContext.insert(AuditEventEntityMapper.toEntity(event))
            }
        }
    }
}
