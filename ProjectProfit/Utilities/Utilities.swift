import Foundation

// MARK: - Currency Formatting

private let currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "JPY"
    f.maximumFractionDigits = 0
    return f
}()

func formatCurrency(_ amount: Int) -> String {
    currencyFormatter.string(from: NSNumber(value: amount)) ?? "¥0"
}

// MARK: - Date Formatting

private let mediumDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateStyle = .medium
    return f
}()

func formatDate(_ date: Date) -> String {
    mediumDateFormatter.string(from: date)
}

private let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "M月d日"
    return f
}()

func formatDateShort(_ date: Date) -> String {
    shortDateFormatter.string(from: date)
}

private let yearMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy年M月"
    return f
}()

func formatYearMonth(_ date: Date) -> String {
    yearMonthFormatter.string(from: date)
}

func todayDate() -> Date {
    Calendar.current.startOfDay(for: Date())
}

func monthString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    return formatter.string(from: date)
}

func startOfMonth(_ date: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: components) ?? date
}

func endOfMonth(_ date: Date) -> Date {
    let calendar = Calendar.current
    guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
          let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) else {
        return date
    }
    return end
}

func startOfYear(_ year: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
}

func endOfYear(_ year: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31)) ?? Date()
}

// MARK: - Next Registration Date

struct NextRegistrationInfo {
    let date: Date
    let label: String
    let daysUntil: Int
}

func getNextRegistrationDate(
    frequency: RecurringFrequency,
    dayOfMonth: Int,
    monthOfYear: Int?,
    isActive: Bool,
    lastGeneratedDate: Date?
) -> NextRegistrationInfo? {
    guard isActive else { return nil }

    let calendar = Calendar.current
    let now = todayDate()
    let comps = calendar.dateComponents([.year, .month, .day], from: now)
    guard let currentYear = comps.year, let currentMonth = comps.month, let currentDay = comps.day else { return nil }

    var nextYear = currentYear
    var nextMonth = currentMonth
    let nextDay = dayOfMonth

    if frequency == .monthly {
        if currentDay >= dayOfMonth {
            nextMonth += 1
            if nextMonth > 12 {
                nextMonth = 1
                nextYear += 1
            }
        }
    } else {
        let targetMonth = monthOfYear ?? 1
        if currentMonth > targetMonth || (currentMonth == targetMonth && currentDay >= dayOfMonth) {
            nextYear += 1
        }
        nextMonth = targetMonth
    }

    guard let nextDate = calendar.date(from: DateComponents(year: nextYear, month: nextMonth, day: nextDay)) else {
        return nil
    }

    let daysUntil = calendar.dateComponents([.day], from: now, to: nextDate).day ?? 0

    let label: String
    switch daysUntil {
    case 0: label = "今日"
    case 1: label = "明日"
    case 2...7: label = "\(daysUntil)日後"
    case 8...30:
        let weeks = daysUntil / 7
        label = "約\(weeks)週間後"
    default:
        let months = daysUntil / 30
        label = "約\(months)ヶ月後"
    }

    return NextRegistrationInfo(date: nextDate, label: label, daysUntil: daysUntil)
}

// MARK: - Pro-Rata (日割り) Calculation

struct ProRataResult {
    let projectId: UUID
    let activeDays: Int
    let totalDays: Int
    let amount: Int
    let ratio: Int
}

/// 月内の稼働日数に基づいて日割り金額を計算する
func calculateProRataAmount(totalAmount: Int, activeDays: Int, totalDays: Int) -> Int {
    guard totalDays > 0, activeDays >= 0 else { return 0 }
    if activeDays >= totalDays { return totalAmount }
    return totalAmount * activeDays / totalDays
}

/// 月の日数を返す
func daysInMonth(year: Int, month: Int) -> Int {
    let calendar = Calendar.current
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
          let range = calendar.range(of: .day, in: .month, for: date)
    else { return 30 }
    return range.count
}

/// プロジェクト完了に伴いアロケーションを日割り再分配する
/// - completedAt: 完了日
/// - transactionDate: 取引の対象月（この月の1日〜末日で計算）
/// - originalAllocations: 元のアロケーション
/// - activeProjectIds: 現在アクティブなプロジェクトIDの集合
/// - Returns: 日割り再分配後のアロケーション
func redistributeAllocationsForCompletion(
    totalAmount: Int,
    completedProjectId: UUID,
    completedAt: Date,
    transactionDate: Date,
    originalAllocations: [Allocation],
    activeProjectIds: Set<UUID>
) -> [Allocation] {
    let calendar = Calendar.current
    let txComps = calendar.dateComponents([.year, .month], from: transactionDate)
    let compComps = calendar.dateComponents([.year, .month, .day], from: completedAt)
    guard let txYear = txComps.year, let txMonth = txComps.month,
          let compYear = compComps.year, let compMonth = compComps.month,
          let compDay = compComps.day
    else { return originalAllocations }

    let totalDays = daysInMonth(year: txYear, month: txMonth)

    // 完了プロジェクトの稼働日数を決定
    let activeDays: Int
    if compYear == txYear && compMonth == txMonth {
        // 同月に完了: 完了日までの日数
        activeDays = compDay
    } else if compYear < txYear || (compYear == txYear && compMonth < txMonth) {
        // 完了月より後の月: 稼働日数0
        activeDays = 0
    } else {
        // 完了月より前の月: フル稼働
        return originalAllocations
    }

    guard let completedAlloc = originalAllocations.first(where: { $0.projectId == completedProjectId }) else {
        return originalAllocations
    }

    let completedOriginalAmount = totalAmount * completedAlloc.ratio / 100
    let proratedAmount = calculateProRataAmount(totalAmount: completedOriginalAmount, activeDays: activeDays, totalDays: totalDays)
    let redistributableAmount = completedOriginalAmount - proratedAmount

    // 完了プロジェクト以外のアクティブなプロジェクトを取得
    let otherActiveAllocs = originalAllocations.filter {
        $0.projectId != completedProjectId && activeProjectIds.contains($0.projectId)
    }

    guard !otherActiveAllocs.isEmpty else {
        // 他にアクティブなプロジェクトがない場合、完了プロジェクトのみ日割り
        return originalAllocations.map { alloc in
            if alloc.projectId == completedProjectId {
                return Allocation(projectId: alloc.projectId, ratio: alloc.ratio, amount: proratedAmount)
            }
            return alloc
        }
    }

    let otherTotalRatio = otherActiveAllocs.reduce(0) { $0 + $1.ratio }

    var result: [Allocation] = []
    var distributedSoFar = 0

    for alloc in originalAllocations {
        if alloc.projectId == completedProjectId {
            result.append(Allocation(projectId: alloc.projectId, ratio: alloc.ratio, amount: proratedAmount))
        } else if activeProjectIds.contains(alloc.projectId) {
            let extraShare = otherTotalRatio > 0
                ? redistributableAmount * alloc.ratio / otherTotalRatio
                : 0
            let newAmount = alloc.amount + extraShare
            distributedSoFar += extraShare
            result.append(Allocation(projectId: alloc.projectId, ratio: alloc.ratio, amount: newAmount))
        } else {
            result.append(alloc)
        }
    }

    // 端数調整: 最後のアクティブプロジェクトに残りを加算
    let remainder = redistributableAmount - distributedSoFar
    if remainder != 0, let lastActiveIdx = result.lastIndex(where: { activeProjectIds.contains($0.projectId) && $0.projectId != completedProjectId }) {
        let last = result[lastActiveIdx]
        result[lastActiveIdx] = Allocation(projectId: last.projectId, ratio: last.ratio, amount: last.amount + remainder)
    }

    return result
}

/// 年の日数を返す
func daysInYear(_ year: Int) -> Int {
    let calendar = Calendar.current
    guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
          let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
    else { return 365 }
    return calendar.dateComponents([.day], from: start, to: end).day ?? 365
}

/// 年額取引のプロジェクト完了に伴い、年間の稼働期間に基づいて日割り再分配する
/// - transactionYear: 取引の対象年（この年の1月1日〜12月31日で計算）
func redistributeAllocationsForYearlyCompletion(
    totalAmount: Int,
    completedProjectId: UUID,
    completedAt: Date,
    transactionYear: Int,
    originalAllocations: [Allocation],
    activeProjectIds: Set<UUID>
) -> [Allocation] {
    let calendar = Calendar.current
    let compYear = calendar.component(.year, from: completedAt)

    let totalDays = daysInYear(transactionYear)

    // 完了プロジェクトの年間稼働日数を決定
    let activeDays: Int
    if compYear > transactionYear {
        // 完了年が取引年より後: フル稼働
        return originalAllocations
    } else if compYear < transactionYear {
        // 完了年が取引年より前: 稼働日数0
        activeDays = 0
    } else {
        // 同年に完了: 年初から完了日までの日数
        guard let yearStart = calendar.date(from: DateComponents(year: transactionYear, month: 1, day: 1)) else {
            return originalAllocations
        }
        activeDays = (calendar.dateComponents([.day], from: yearStart, to: completedAt).day ?? 0) + 1
    }

    guard let completedAlloc = originalAllocations.first(where: { $0.projectId == completedProjectId }) else {
        return originalAllocations
    }

    let completedOriginalAmount = totalAmount * completedAlloc.ratio / 100
    let proratedAmount = calculateProRataAmount(totalAmount: completedOriginalAmount, activeDays: activeDays, totalDays: totalDays)
    let redistributableAmount = completedOriginalAmount - proratedAmount

    let otherActiveAllocs = originalAllocations.filter {
        $0.projectId != completedProjectId && activeProjectIds.contains($0.projectId)
    }

    guard !otherActiveAllocs.isEmpty else {
        return originalAllocations.map { alloc in
            if alloc.projectId == completedProjectId {
                return Allocation(projectId: alloc.projectId, ratio: alloc.ratio, amount: proratedAmount)
            }
            return alloc
        }
    }

    let otherTotalRatio = otherActiveAllocs.reduce(0) { $0 + $1.ratio }

    var result: [Allocation] = []
    var distributedSoFar = 0

    for alloc in originalAllocations {
        if alloc.projectId == completedProjectId {
            result.append(Allocation(projectId: alloc.projectId, ratio: alloc.ratio, amount: proratedAmount))
        } else if activeProjectIds.contains(alloc.projectId) {
            let extraShare = otherTotalRatio > 0
                ? redistributableAmount * alloc.ratio / otherTotalRatio
                : 0
            let newAmount = alloc.amount + extraShare
            distributedSoFar += extraShare
            result.append(Allocation(projectId: alloc.projectId, ratio: alloc.ratio, amount: newAmount))
        } else {
            result.append(alloc)
        }
    }

    let remainder = redistributableAmount - distributedSoFar
    if remainder != 0, let lastActiveIdx = result.lastIndex(where: { activeProjectIds.contains($0.projectId) && $0.projectId != completedProjectId }) {
        let last = result[lastActiveIdx]
        result[lastActiveIdx] = Allocation(projectId: last.projectId, ratio: last.ratio, amount: last.amount + remainder)
    }

    return result
}

// MARK: - Equal Split Allocation

func calculateEqualSplitAllocations(amount: Int, projectIds: [UUID]) -> [Allocation] {
    guard !projectIds.isEmpty else { return [] }
    let count = projectIds.count
    let baseAmount = amount / count
    let amountRemainder = amount - (baseAmount * count)
    let baseRatio = 100 / count
    let ratioRemainder = 100 - (baseRatio * count)

    return projectIds.enumerated().map { index, projectId in
        let isLast = index == count - 1
        return Allocation(
            projectId: projectId,
            ratio: isLast ? baseRatio + ratioRemainder : baseRatio,
            amount: isLast ? baseAmount + amountRemainder : baseAmount
        )
    }
}

// MARK: - CSV Import

struct CSVImportResult {
    let successCount: Int
    let errorCount: Int
    let errors: [String]
}

func parseCSV(
    csvString: String,
    getOrCreateProject: (String) -> UUID,
    getCategoryId: (String, TransactionType) -> String?
) -> [(type: TransactionType, amount: Int, date: Date, categoryId: String, memo: String, projectName: String, ratio: Int, allocations: [(projectName: String, ratio: Int)])] {
    let cleaned = csvString.replacingOccurrences(of: "\u{FEFF}", with: "")
    let lines = cleaned.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    guard lines.count > 1 else { return [] }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    var results: [(type: TransactionType, amount: Int, date: Date, categoryId: String, memo: String, projectName: String, ratio: Int, allocations: [(projectName: String, ratio: Int)])] = []

    for line in lines.dropFirst() {
        let fields = parseCSVLine(line)
        guard fields.count >= 6 else { continue }

        let dateStr = fields[0]
        let typeStr = fields[1]
        let amountStr = fields[2]
        let categoryName = fields[3]
        let projectStr = fields[4]
        let memo = fields[5]

        guard let date = dateFormatter.date(from: dateStr) else { continue }

        let type: TransactionType = typeStr == "収益" ? .income : .expense

        guard let amount = Int(amountStr), amount > 0 else { continue }

        guard let categoryId = getCategoryId(categoryName, type) else { continue }

        let allocations = parseProjectAllocations(projectStr)
        guard !allocations.isEmpty else { continue }

        for allocation in allocations {
            let projectId = getOrCreateProject(allocation.name)
            results.append((
                type: type,
                amount: amount,
                date: date,
                categoryId: categoryId,
                memo: memo,
                projectName: allocation.name,
                ratio: allocation.ratio,
                allocations: allocations.map { (projectName: $0.name, ratio: $0.ratio) }
            ))
        }
    }

    // Deduplicate: group by unique transaction (all fields except per-allocation breakdown)
    var seen = Set<String>()
    var deduplicated: [(type: TransactionType, amount: Int, date: Date, categoryId: String, memo: String, projectName: String, ratio: Int, allocations: [(projectName: String, ratio: Int)])] = []

    for entry in results {
        let key = "\(entry.date)-\(entry.type)-\(entry.amount)-\(entry.categoryId)-\(entry.memo)"
        if !seen.contains(key) {
            seen.insert(key)
            deduplicated.append(entry)
        }
    }

    return deduplicated
}

private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false

    for char in line {
        if char == "\"" {
            inQuotes.toggle()
        } else if char == "," && !inQuotes {
            fields.append(current)
            current = ""
        } else {
            current.append(char)
        }
    }
    fields.append(current)
    return fields
}

private struct ProjectAllocation {
    let name: String
    let ratio: Int
}

private func parseProjectAllocations(_ projectStr: String) -> [ProjectAllocation] {
    let parts = projectStr.components(separatedBy: "; ")
    var allocations: [ProjectAllocation] = []

    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }

        if let openParen = trimmed.lastIndex(of: "("),
           let closeParen = trimmed.lastIndex(of: ")"),
           openParen < closeParen {
            let name = String(trimmed[trimmed.startIndex..<openParen])
            let ratioStart = trimmed.index(after: openParen)
            let ratioStr = String(trimmed[ratioStart..<closeParen]).replacingOccurrences(of: "%", with: "")
            if let ratio = Int(ratioStr), !name.isEmpty {
                allocations.append(ProjectAllocation(name: name, ratio: ratio))
            }
        } else {
            // No ratio specified, assume 100%
            allocations.append(ProjectAllocation(name: trimmed, ratio: 100))
        }
    }

    return allocations
}

// MARK: - CSV Export

func generateCSV(
    transactions: [PPTransaction],
    getCategory: (String) -> PPCategory?,
    getProject: (UUID) -> PPProject?
) -> String {
    let bom = "\u{FEFF}"
    let headers = "\"日付\",\"種類\",\"金額\",\"カテゴリ\",\"プロジェクト\",\"メモ\""

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let rows = transactions.map { t -> String in
        let dateStr = dateFormatter.string(from: t.date)
        let typeStr = t.type == .income ? "収益" : "経費"
        let category = getCategory(t.categoryId)?.name ?? ""
        let projectNames = t.allocations
            .compactMap { a -> String? in
                guard let project = getProject(a.projectId) else { return nil }
                return "\(project.name)(\(a.ratio)%)"
            }
            .joined(separator: "; ")
        let escapedCategory = category.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedProjectNames = projectNames.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedMemo = t.memo.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(dateStr)\",\"\(typeStr)\",\"\(t.amount)\",\"\(escapedCategory)\",\"\(escapedProjectNames)\",\"\(escapedMemo)\""
    }

    return bom + ([headers] + rows).joined(separator: "\n")
}
