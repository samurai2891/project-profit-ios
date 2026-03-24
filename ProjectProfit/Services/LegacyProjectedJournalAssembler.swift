import Foundation

struct ProjectedLegacyJournalSet {
    let businessId: UUID?
    let entries: [PPJournalEntry]
    let lines: [PPJournalLine]

    static let empty = ProjectedLegacyJournalSet(businessId: nil, entries: [], lines: [])
}

enum LegacyProjectedJournalAssembler {
    static func assemble(
        businessId: UUID,
        fiscalYear requestedFiscalYear: Int? = nil,
        canonicalAccounts: [CanonicalAccount],
        canonicalJournals: [CanonicalJournalEntry],
        legacyEntries: [PPJournalEntry],
        legacyLines: [PPJournalLine],
        supplementalSourcePrefixes: Set<String>
    ) -> ProjectedLegacyJournalSet {
        let projectedEntries = projectEntries(canonicalJournals)
        let projectedLines = projectLines(canonicalJournals, canonicalAccounts: canonicalAccounts)

        let prefixedLegacyEntries = legacyEntries.filter { entry in
            guard supplementalSourcePrefixes.contains(where: { entry.sourceKey.hasPrefix($0) }) else {
                return false
            }
            guard let requestedFiscalYear else {
                return true
            }
            return fiscalYear(
                for: entry.date,
                startMonth: FiscalYearSettings.startMonth
            ) == requestedFiscalYear
        }
        guard !prefixedLegacyEntries.isEmpty else {
            return ProjectedLegacyJournalSet(
                businessId: businessId,
                entries: projectedEntries,
                lines: projectedLines
            )
        }

        let projectedEntryIds = Set(projectedEntries.map(\.id))
        let supplementalEntries = prefixedLegacyEntries.filter { !projectedEntryIds.contains($0.id) }
        let supplementalEntryIds = Set(supplementalEntries.map(\.id))
        let supplementalLines = legacyLines.filter { supplementalEntryIds.contains($0.entryId) }

        let mergedEntries = (projectedEntries + supplementalEntries).sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.date > rhs.date
        }

        return ProjectedLegacyJournalSet(
            businessId: businessId,
            entries: mergedEntries,
            lines: projectedLines + supplementalLines
        )
    }

    static func projectedLegacyEntryType(for entry: CanonicalJournalEntry) -> JournalEntryType {
        switch entry.entryType {
        case .opening:
            return .opening
        case .closing:
            return .closing
        case .normal, .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
            return .auto
        }
    }

    private static func projectEntries(_ journals: [CanonicalJournalEntry]) -> [PPJournalEntry] {
        var entries: [PPJournalEntry] = []
        entries.reserveCapacity(journals.count)
        for entry in journals {
            entries.append(
                PPJournalEntry(
                    id: entry.id,
                    sourceKey: "canonical:\(entry.id.uuidString)",
                    date: entry.journalDate,
                    entryType: projectedLegacyEntryType(for: entry),
                    memo: entry.description,
                    isPosted: entry.approvedAt != nil,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            )
        }
        return entries
    }

    private static func projectLines(
        _ journals: [CanonicalJournalEntry],
        canonicalAccounts: [CanonicalAccount]
    ) -> [PPJournalLine] {
        let accountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })
        let projectedLineCount = journals.reduce(into: 0) { $0 += $1.lines.count }
        var projectedLines: [PPJournalLine] = []
        projectedLines.reserveCapacity(projectedLineCount)

        for entry in journals {
            for line in orderedLines(for: entry.lines) {
                let legacyAccountId = accountsById[line.accountId]?.legacyAccountId ?? line.accountId.uuidString
                projectedLines.append(PPJournalLine(
                    id: line.id,
                    entryId: entry.id,
                    accountId: legacyAccountId,
                    debit: NSDecimalNumber(decimal: line.debitAmount).intValue,
                    credit: NSDecimalNumber(decimal: line.creditAmount).intValue,
                    memo: "",
                    displayOrder: line.sortOrder,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                ))
            }
        }
        return projectedLines
    }

    private static func orderedLines(for lines: [JournalLine]) -> [JournalLine] {
        guard lines.count > 1 else {
            return lines
        }
        for index in 1..<lines.count where lines[index - 1].sortOrder > lines[index].sortOrder {
            return lines.sorted { $0.sortOrder < $1.sortOrder }
        }
        return lines
    }
}
