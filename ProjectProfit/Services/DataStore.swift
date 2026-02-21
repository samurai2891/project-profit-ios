import os
import SwiftData
import SwiftUI

@MainActor
@Observable
class DataStore {
    private var modelContext: ModelContext

    var projects: [PPProject] = []
    var transactions: [PPTransaction] = []
    var categories: [PPCategory] = []
    var recurringTransactions: [PPRecurringTransaction] = []
    var isLoading = true
    var lastError: AppError?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Initialization

    func loadData() {
        do {
            let projectDescriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            projects = try modelContext.fetch(projectDescriptor)

            let transactionDescriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            transactions = try modelContext.fetch(transactionDescriptor)

            let categoryDescriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
            categories = try modelContext.fetch(categoryDescriptor)

            let recurringDescriptor = FetchDescriptor<PPRecurringTransaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            recurringTransactions = try modelContext.fetch(recurringDescriptor)

            if categories.isEmpty {
                seedDefaultCategories()
            } else {
                seedMissingCategories()
            }
        } catch {
            AppLogger.dataStore.error("Failed to load data: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
        isLoading = false
    }

    private func seedDefaultCategories() {
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
        save()
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
        categories = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Add any new default categories that don't exist yet (for app updates)
    private func seedMissingCategories() {
        let existingIds = Set(categories.map(\.id))
        var added = false
        for cat in DEFAULT_CATEGORIES where !existingIds.contains(cat.id) {
            let category = PPCategory(
                id: cat.id,
                name: cat.name,
                type: cat.type,
                icon: cat.icon,
                isDefault: true
            )
            modelContext.insert(category)
            added = true
        }
        if added {
            save()
            refreshCategories()
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            AppLogger.dataStore.error("Save failed: \(error.localizedDescription)")
            lastError = .saveFailed(underlying: error)
        }
    }

    private func refreshProjects() {
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        projects = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func refreshTransactions() {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        transactions = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func refreshCategories() {
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
        categories = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func refreshRecurring() {
        let descriptor = FetchDescriptor<PPRecurringTransaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recurringTransactions = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Project CRUD

    @discardableResult
    func addProject(name: String, description: String) -> PPProject {
        let project = PPProject(name: name, projectDescription: description)
        modelContext.insert(project)
        save()
        refreshProjects()
        return project
    }

    func updateProject(id: UUID, name: String? = nil, description: String? = nil, status: ProjectStatus? = nil) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        if let name { project.name = name }
        if let description { project.projectDescription = description }
        if let status { project.status = status }
        project.updatedAt = Date()
        save()
        refreshProjects()
    }

    func deleteProject(id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }

        // Remove allocations referencing this project from transactions
        for transaction in transactions {
            let filtered = transaction.allocations.filter { $0.projectId != id }
            if filtered.count != transaction.allocations.count {
                if filtered.isEmpty {
                    modelContext.delete(transaction)
                } else {
                    transaction.allocations = filtered
                }
            }
        }

        // Remove allocations from recurring
        for recurring in recurringTransactions {
            let filtered = recurring.allocations.filter { $0.projectId != id }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty {
                    modelContext.delete(recurring)
                } else {
                    recurring.allocations = filtered
                }
            }
        }

        modelContext.delete(project)
        save()
        refreshProjects()
        refreshTransactions()
        refreshRecurring()
    }

    func deleteProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        for id in ids {
            guard let project = projects.first(where: { $0.id == id }) else { continue }

            for transaction in transactions {
                let filtered = transaction.allocations.filter { $0.projectId != id }
                if filtered.count != transaction.allocations.count {
                    if filtered.isEmpty {
                        modelContext.delete(transaction)
                    } else {
                        transaction.allocations = filtered
                    }
                }
            }

            for recurring in recurringTransactions {
                let filtered = recurring.allocations.filter { $0.projectId != id }
                if filtered.count != recurring.allocations.count {
                    if filtered.isEmpty {
                        modelContext.delete(recurring)
                    } else {
                        recurring.allocations = filtered
                    }
                }
            }

            modelContext.delete(project)
        }

        save()
        refreshProjects()
        refreshTransactions()
        refreshRecurring()
    }

    func getProject(id: UUID) -> PPProject? {
        projects.first { $0.id == id }
    }

    // MARK: - Transaction CRUD

    @discardableResult
    func addTransaction(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        receiptImagePath: String? = nil,
        lineItems: [ReceiptLineItem] = []
    ) -> PPTransaction {
        let allocs = allocations.map { Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: amount * $0.ratio / 100) }
        let transaction = PPTransaction(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocs,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems
        )
        modelContext.insert(transaction)
        save()
        refreshTransactions()
        return transaction
    }

    func updateTransaction(
        id: UUID,
        type: TransactionType? = nil,
        amount: Int? = nil,
        date: Date? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        allocations: [(projectId: UUID, ratio: Int)]? = nil,
        receiptImagePath: String?? = nil,
        lineItems: [ReceiptLineItem]? = nil
    ) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        if let type { transaction.type = type }
        if let date { transaction.date = date }
        if let categoryId { transaction.categoryId = categoryId }
        if let memo { transaction.memo = memo }
        if let receiptImagePath { transaction.receiptImagePath = receiptImagePath }
        if let lineItems { transaction.lineItems = lineItems }

        let finalAmount = amount ?? transaction.amount
        if let amount { transaction.amount = amount }

        if let allocations {
            transaction.allocations = allocations.map {
                Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: finalAmount * $0.ratio / 100)
            }
        } else if amount != nil {
            transaction.allocations = transaction.allocations.map {
                Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: finalAmount * $0.ratio / 100)
            }
        }

        transaction.updatedAt = Date()
        save()
        refreshTransactions()
    }

    func deleteTransaction(id: UUID) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        if let imagePath = transaction.receiptImagePath {
            ReceiptImageStore.deleteImage(fileName: imagePath)
        }
        modelContext.delete(transaction)
        save()
        refreshTransactions()
    }

    func removeReceiptImage(transactionId: UUID) {
        guard let transaction = transactions.first(where: { $0.id == transactionId }) else { return }
        if let imagePath = transaction.receiptImagePath {
            ReceiptImageStore.deleteImage(fileName: imagePath)
        }
        transaction.receiptImagePath = nil
        transaction.updatedAt = Date()
        save()
        refreshTransactions()
    }

    func getTransaction(id: UUID) -> PPTransaction? {
        transactions.first { $0.id == id }
    }

    // MARK: - Category CRUD

    @discardableResult
    func addCategory(name: String, type: CategoryType, icon: String) -> PPCategory {
        let category = PPCategory(id: UUID().uuidString, name: name, type: type, icon: icon)
        modelContext.insert(category)
        save()
        refreshCategories()
        return category
    }

    func updateCategory(id: String, name: String? = nil, type: CategoryType? = nil, icon: String? = nil) {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        if let name { category.name = name }
        if let type { category.type = type }
        if let icon { category.icon = icon }
        save()
        refreshCategories()
    }

    func deleteCategory(id: String) {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        guard !category.isDefault else { return }
        modelContext.delete(category)
        save()
        refreshCategories()
    }

    func getCategory(id: String) -> PPCategory? {
        categories.first { $0.id == id }
    }

    // MARK: - Recurring CRUD

    @discardableResult
    func addRecurring(
        name: String,
        type: TransactionType,
        amount: Int,
        categoryId: String,
        memo: String,
        allocationMode: AllocationMode = .manual,
        allocations: [(projectId: UUID, ratio: Int)],
        frequency: RecurringFrequency,
        dayOfMonth: Int,
        monthOfYear: Int? = nil
    ) -> PPRecurringTransaction {
        let allocs: [Allocation]
        switch allocationMode {
        case .equalAll:
            allocs = []
        case .manual:
            allocs = allocations.map { Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: amount * $0.ratio / 100) }
        }
        let recurring = PPRecurringTransaction(
            name: name,
            type: type,
            amount: amount,
            categoryId: categoryId,
            memo: memo,
            allocationMode: allocationMode,
            allocations: allocs,
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            monthOfYear: monthOfYear
        )
        modelContext.insert(recurring)
        save()
        refreshRecurring()
        return recurring
    }

    func updateRecurring(
        id: UUID,
        name: String? = nil,
        type: TransactionType? = nil,
        amount: Int? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        allocationMode: AllocationMode? = nil,
        allocations: [(projectId: UUID, ratio: Int)]? = nil,
        frequency: RecurringFrequency? = nil,
        dayOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        isActive: Bool? = nil,
        notificationTiming: NotificationTiming? = nil,
        skipDates: [Date]? = nil
    ) {
        guard let recurring = recurringTransactions.first(where: { $0.id == id }) else { return }
        if let name { recurring.name = name }
        if let type { recurring.type = type }
        if let categoryId { recurring.categoryId = categoryId }
        if let memo { recurring.memo = memo }
        if let allocationMode { recurring.allocationMode = allocationMode }
        if let frequency {
            recurring.frequency = frequency
            if frequency == .monthly {
                recurring.monthOfYear = nil
            } else if let monthOfYear {
                recurring.monthOfYear = monthOfYear
            }
        } else if let monthOfYear {
            recurring.monthOfYear = monthOfYear
        }
        if let dayOfMonth { recurring.dayOfMonth = min(28, max(1, dayOfMonth)) }
        if let isActive { recurring.isActive = isActive }
        if let notificationTiming { recurring.notificationTiming = notificationTiming }
        if let skipDates { recurring.skipDates = skipDates }

        let resolvedMode = allocationMode ?? recurring.allocationMode
        let finalAmount = amount ?? recurring.amount
        if let amount { recurring.amount = amount }

        switch resolvedMode {
        case .equalAll:
            recurring.allocations = []
        case .manual:
            if let allocations {
                recurring.allocations = allocations.map {
                    Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: finalAmount * $0.ratio / 100)
                }
            } else if amount != nil {
                recurring.allocations = recurring.allocations.map {
                    Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: finalAmount * $0.ratio / 100)
                }
            }
        }

        recurring.updatedAt = Date()
        save()
        refreshRecurring()
    }

    func deleteRecurring(id: UUID) {
        guard let recurring = recurringTransactions.first(where: { $0.id == id }) else { return }
        modelContext.delete(recurring)
        save()
        refreshRecurring()
    }

    func getRecurring(id: UUID) -> PPRecurringTransaction? {
        recurringTransactions.first { $0.id == id }
    }

    // MARK: - Process Recurring Transactions

    @discardableResult
    func processRecurringTransactions() -> Int {
        let calendar = Calendar.current
        let today = todayDate()
        let todayComps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = todayComps.year, let currentMonth = todayComps.month, let currentDay = todayComps.day else { return 0 }

        var generatedCount = 0

        for recurring in recurringTransactions {
            guard recurring.isActive else { continue }
            if recurring.allocationMode == .manual && recurring.allocations.isEmpty { continue }

            var shouldGenerate = false
            var transactionDate: Date?

            if recurring.frequency == .monthly {
                let targetDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: recurring.dayOfMonth))
                if currentDay >= recurring.dayOfMonth {
                    guard let currentMonthStart = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: 1)) else { continue }
                    if let lastGen = recurring.lastGeneratedDate {
                        let lastGenMonth = calendar.dateComponents([.year, .month], from: lastGen)
                        let currentMonthComps = calendar.dateComponents([.year, .month], from: currentMonthStart)
                        if lastGenMonth.year != currentMonthComps.year || lastGenMonth.month != currentMonthComps.month {
                            shouldGenerate = true
                            transactionDate = targetDate
                        }
                    } else {
                        shouldGenerate = true
                        transactionDate = targetDate
                    }
                }
            } else {
                let targetMonth = recurring.monthOfYear ?? 1
                let targetDate = calendar.date(from: DateComponents(year: currentYear, month: targetMonth, day: recurring.dayOfMonth))
                if currentMonth > targetMonth || (currentMonth == targetMonth && currentDay >= recurring.dayOfMonth) {
                    if let lastGen = recurring.lastGeneratedDate {
                        let lastGenYear = calendar.component(.year, from: lastGen)
                        if lastGenYear != currentYear {
                            shouldGenerate = true
                            transactionDate = targetDate
                        }
                    } else {
                        shouldGenerate = true
                        transactionDate = targetDate
                    }
                }
            }

            guard shouldGenerate, let txDate = transactionDate else { continue }

            // Check skip dates
            let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
            if isSkipped {
                recurring.lastGeneratedDate = txDate
                recurring.skipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: txDate) }
                recurring.updatedAt = Date()
                continue
            }

            let memo = "[定期] \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")
            let txAllocations: [Allocation]
            switch recurring.allocationMode {
            case .equalAll:
                let activeProjectIds = projects.filter { $0.status == .active }.map(\.id)
                guard !activeProjectIds.isEmpty else { continue }
                txAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: activeProjectIds)
            case .manual:
                txAllocations = recurring.allocations.map {
                    Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: recurring.amount * $0.ratio / 100)
                }
            }
            let transaction = PPTransaction(
                type: recurring.type,
                amount: recurring.amount,
                date: txDate,
                categoryId: recurring.categoryId,
                memo: memo,
                allocations: txAllocations,
                recurringId: recurring.id
            )
            modelContext.insert(transaction)

            recurring.lastGeneratedDate = txDate
            recurring.updatedAt = Date()
            generatedCount += 1
        }

        if generatedCount > 0 {
            save()
            refreshRecurring()
        }

        return generatedCount
    }

    // MARK: - Summary Functions

    func getProjectSummary(projectId: UUID) -> ProjectSummary? {
        guard let project = getProject(id: projectId) else { return nil }

        var totalIncome = 0
        var totalExpense = 0

        for t in transactions {
            if let alloc = t.allocations.first(where: { $0.projectId == projectId }) {
                if t.type == .income {
                    totalIncome += alloc.amount
                } else {
                    totalExpense += alloc.amount
                }
            }
        }

        let profit = totalIncome - totalExpense
        let profitMargin = totalIncome > 0 ? Double(profit) / Double(totalIncome) * 100 : 0

        return ProjectSummary(
            id: projectId,
            projectName: project.name,
            status: project.status,
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            profit: profit,
            profitMargin: profitMargin
        )
    }

    func getAllProjectSummaries() -> [ProjectSummary] {
        projects.compactMap { getProjectSummary(projectId: $0.id) }
    }

    func getOverallSummary(startDate: Date? = nil, endDate: Date? = nil) -> OverallSummary {
        var totalIncome = 0
        var totalExpense = 0

        for t in transactions {
            if let start = startDate, t.date < start { continue }
            if let end = endDate, t.date > end { continue }
            if t.type == .income {
                totalIncome += t.amount
            } else {
                totalExpense += t.amount
            }
        }

        let netProfit = totalIncome - totalExpense
        let profitMargin = totalIncome > 0 ? Double(netProfit) / Double(totalIncome) * 100 : 0

        return OverallSummary(totalIncome: totalIncome, totalExpense: totalExpense, netProfit: netProfit, profitMargin: profitMargin)
    }

    func getCategorySummaries(type: TransactionType, startDate: Date? = nil, endDate: Date? = nil) -> [CategorySummary] {
        var totals: [String: Int] = [:]
        var grandTotal = 0

        for t in transactions {
            guard t.type == type else { continue }
            if let start = startDate, t.date < start { continue }
            if let end = endDate, t.date > end { continue }
            totals[t.categoryId, default: 0] += t.amount
            grandTotal += t.amount
        }

        return totals.map { categoryId, total in
            let name = getCategory(id: categoryId)?.name ?? "不明"
            let percentage = grandTotal > 0 ? Double(total) / Double(grandTotal) * 100 : 0
            return CategorySummary(categoryId: categoryId, categoryName: name, total: total, percentage: percentage)
        }.sorted { $0.total > $1.total }
    }

    func getMonthlySummaries(year: Int) -> [MonthlySummary] {
        var monthlyData: [String: (income: Int, expense: Int)] = [:]
        for m in 1...12 {
            let key = String(format: "%d-%02d", year, m)
            monthlyData[key] = (0, 0)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        for t in transactions {
            let month = formatter.string(from: t.date)
            guard month.hasPrefix(String(year)), monthlyData[month] != nil else { continue }
            guard var data = monthlyData[month] else { continue }
            if t.type == .income {
                data.income += t.amount
            } else {
                data.expense += t.amount
            }
            monthlyData[month] = data
        }

        return monthlyData.sorted { $0.key < $1.key }.map { key, data in
            MonthlySummary(month: key, income: data.income, expense: data.expense, profit: data.income - data.expense)
        }
    }

    // MARK: - Filter & Sort

    func getFilteredTransactions(filter: TransactionFilter, sort: TransactionSort? = nil) -> [PPTransaction] {
        var result = transactions.filter { t in
            if let start = filter.startDate, t.date < start { return false }
            if let end = filter.endDate, t.date > end { return false }
            if let projectId = filter.projectId, !t.allocations.contains(where: { $0.projectId == projectId }) { return false }
            if let categoryId = filter.categoryId, t.categoryId != categoryId { return false }
            if let type = filter.type, t.type != type { return false }
            return true
        }

        let sortSpec = sort ?? TransactionSort(field: .date, order: .desc)
        result.sort { a, b in
            let comparison: Bool
            switch sortSpec.field {
            case .date:
                comparison = a.date < b.date
            case .amount:
                comparison = a.amount < b.amount
            }
            return sortSpec.order == .desc ? !comparison : comparison
        }

        return result
    }

    // MARK: - CSV Import

    func importTransactions(from csvString: String) -> CSVImportResult {
        var successCount = 0
        var errorCount = 0
        var errors: [String] = []

        let parsed = parseCSV(
            csvString: csvString,
            getOrCreateProject: { [self] name in
                if let existing = projects.first(where: { $0.name == name }) {
                    return existing.id
                }
                let newProject = addProject(name: name, description: "")
                return newProject.id
            },
            getCategoryId: { [self] name, type in
                let categoryType: CategoryType = type == .income ? .income : .expense
                if let existing = categories.first(where: { $0.name == name && $0.type == categoryType }) {
                    return existing.id
                }
                // Also try matching by name only as a fallback
                if let existing = categories.first(where: { $0.name == name }) {
                    return existing.id
                }
                return nil
            }
        )

        for entry in parsed {
            let allocations: [(projectId: UUID, ratio: Int)] = entry.allocations.compactMap { alloc in
                if let project = projects.first(where: { $0.name == alloc.projectName }) {
                    return (projectId: project.id, ratio: alloc.ratio)
                }
                return nil
            }

            guard !allocations.isEmpty else {
                errorCount += 1
                errors.append("プロジェクトが見つかりません: \(entry.projectName)")
                continue
            }

            let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
            guard totalRatio > 0, totalRatio <= 100 else {
                errorCount += 1
                errors.append("配分比率が不正です（合計: \(totalRatio)%）")
                continue
            }

            addTransaction(
                type: entry.type,
                amount: entry.amount,
                date: entry.date,
                categoryId: entry.categoryId,
                memo: entry.memo,
                allocations: allocations
            )
            successCount += 1
        }

        return CSVImportResult(successCount: successCount, errorCount: errorCount, errors: errors)
    }

    // MARK: - Bulk Delete

    func deleteAllData() {
        // Delete all receipt images
        for t in transactions {
            if let imagePath = t.receiptImagePath {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        for p in projects { modelContext.delete(p) }
        for t in transactions { modelContext.delete(t) }
        for c in categories { modelContext.delete(c) }
        for r in recurringTransactions { modelContext.delete(r) }
        save()
        projects = []
        transactions = []
        categories = []
        recurringTransactions = []
        seedDefaultCategories()
    }
}
