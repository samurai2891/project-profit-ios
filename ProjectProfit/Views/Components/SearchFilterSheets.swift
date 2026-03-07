import SwiftUI

struct EvidenceSearchFormState: Equatable {
    var textQuery = ""
    var useStartDate = false
    var startDate = Calendar.current.startOfDay(for: Date())
    var useEndDate = false
    var endDate = Calendar.current.startOfDay(for: Date())
    var minimumAmountText = ""
    var maximumAmountText = ""
    var counterpartyText = ""
    var registrationNumber = ""
    var selectedProjectId: UUID?
    var fileHash = ""

    var hasActiveFilters: Bool {
        useStartDate
            || useEndDate
            || !minimumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !maximumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !counterpartyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !registrationNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedProjectId != nil
            || !fileHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !textQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var reloadToken: String {
        [
            textQuery,
            useStartDate ? startDate.ISO8601Format() : "nostart",
            useEndDate ? endDate.ISO8601Format() : "noend",
            minimumAmountText,
            maximumAmountText,
            counterpartyText,
            registrationNumber,
            selectedProjectId?.uuidString ?? "noproject",
            fileHash
        ].joined(separator: "|")
    }

    func makeCriteria(
        businessId: UUID?,
        complianceStatus: ComplianceStatus? = nil
    ) -> EvidenceSearchCriteria {
        EvidenceSearchCriteria(
            businessId: businessId,
            dateRange: SearchFilterDateBuilder.makeRange(
                useStart: useStartDate,
                startDate: startDate,
                useEnd: useEndDate,
                endDate: endDate
            ),
            amountRange: SearchFilterDecimalBuilder.makeRange(
                minimumText: minimumAmountText,
                maximumText: maximumAmountText
            ),
            counterpartyText: counterpartyText.nilIfBlank,
            registrationNumber: registrationNumber.nilIfBlank,
            projectId: selectedProjectId,
            fileHash: fileHash.nilIfBlank,
            complianceStatus: complianceStatus,
            textQuery: textQuery.nilIfBlank
        )
    }

    mutating func reset() {
        self = EvidenceSearchFormState()
    }
}

struct JournalSearchFormState: Equatable {
    var textQuery = ""
    var useStartDate = false
    var startDate = Calendar.current.startOfDay(for: Date())
    var useEndDate = false
    var endDate = Calendar.current.startOfDay(for: Date())
    var minimumAmountText = ""
    var maximumAmountText = ""
    var counterpartyText = ""
    var registrationNumber = ""
    var selectedProjectId: UUID?
    var fileHash = ""

    var hasActiveFilters: Bool {
        EvidenceSearchFormState(
            textQuery: textQuery,
            useStartDate: useStartDate,
            startDate: startDate,
            useEndDate: useEndDate,
            endDate: endDate,
            minimumAmountText: minimumAmountText,
            maximumAmountText: maximumAmountText,
            counterpartyText: counterpartyText,
            registrationNumber: registrationNumber,
            selectedProjectId: selectedProjectId,
            fileHash: fileHash
        ).hasActiveFilters
    }

    var reloadToken: String {
        EvidenceSearchFormState(
            textQuery: textQuery,
            useStartDate: useStartDate,
            startDate: startDate,
            useEndDate: useEndDate,
            endDate: endDate,
            minimumAmountText: minimumAmountText,
            maximumAmountText: maximumAmountText,
            counterpartyText: counterpartyText,
            registrationNumber: registrationNumber,
            selectedProjectId: selectedProjectId,
            fileHash: fileHash
        ).reloadToken
    }

    func makeCriteria(businessId: UUID?, taxYear: Int? = nil) -> JournalSearchCriteria {
        JournalSearchCriteria(
            businessId: businessId,
            taxYear: taxYear,
            dateRange: SearchFilterDateBuilder.makeRange(
                useStart: useStartDate,
                startDate: startDate,
                useEnd: useEndDate,
                endDate: endDate
            ),
            amountRange: SearchFilterDecimalBuilder.makeRange(
                minimumText: minimumAmountText,
                maximumText: maximumAmountText
            ),
            counterpartyText: counterpartyText.nilIfBlank,
            registrationNumber: registrationNumber.nilIfBlank,
            projectId: selectedProjectId,
            fileHash: fileHash.nilIfBlank,
            textQuery: textQuery.nilIfBlank
        )
    }

    mutating func reset() {
        self = JournalSearchFormState()
    }
}

struct EvidenceSearchFilterSheet: View {
    @Binding var form: EvidenceSearchFormState
    let projects: [PPProject]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SearchDateSection(
                    useStartDate: $form.useStartDate,
                    startDate: $form.startDate,
                    useEndDate: $form.useEndDate,
                    endDate: $form.endDate
                )
                SearchAmountSection(
                    minimumAmountText: $form.minimumAmountText,
                    maximumAmountText: $form.maximumAmountText
                )
                SearchTextSection(
                    counterpartyText: $form.counterpartyText,
                    registrationNumber: $form.registrationNumber,
                    fileHash: $form.fileHash
                )
                SearchProjectSection(
                    selectedProjectId: $form.selectedProjectId,
                    projects: projects
                )
            }
            .navigationTitle("検索条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("リセット") { form.reset() }
                }
            }
        }
    }
}

struct JournalSearchFilterSheet: View {
    @Binding var form: JournalSearchFormState
    let projects: [PPProject]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SearchDateSection(
                    useStartDate: $form.useStartDate,
                    startDate: $form.startDate,
                    useEndDate: $form.useEndDate,
                    endDate: $form.endDate
                )
                SearchAmountSection(
                    minimumAmountText: $form.minimumAmountText,
                    maximumAmountText: $form.maximumAmountText
                )
                SearchTextSection(
                    counterpartyText: $form.counterpartyText,
                    registrationNumber: $form.registrationNumber,
                    fileHash: $form.fileHash
                )
                SearchProjectSection(
                    selectedProjectId: $form.selectedProjectId,
                    projects: projects
                )
            }
            .navigationTitle("検索条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("リセット") { form.reset() }
                }
            }
        }
    }
}

private struct SearchDateSection: View {
    @Binding var useStartDate: Bool
    @Binding var startDate: Date
    @Binding var useEndDate: Bool
    @Binding var endDate: Date

    var body: some View {
        Section("日付") {
            Toggle("開始日を指定", isOn: $useStartDate)
            if useStartDate {
                DatePicker("開始日", selection: $startDate, displayedComponents: .date)
            }
            Toggle("終了日を指定", isOn: $useEndDate)
            if useEndDate {
                DatePicker("終了日", selection: $endDate, displayedComponents: .date)
            }
        }
    }
}

private struct SearchAmountSection: View {
    @Binding var minimumAmountText: String
    @Binding var maximumAmountText: String

    var body: some View {
        Section("金額") {
            TextField("最小金額", text: $minimumAmountText)
                .keyboardType(.numbersAndPunctuation)
            TextField("最大金額", text: $maximumAmountText)
                .keyboardType(.numbersAndPunctuation)
        }
    }
}

private struct SearchTextSection: View {
    @Binding var counterpartyText: String
    @Binding var registrationNumber: String
    @Binding var fileHash: String

    var body: some View {
        Section("照合キー") {
            TextField("取引先", text: $counterpartyText)
            TextField("T番号", text: $registrationNumber)
                .textInputAutocapitalization(.characters)
            TextField("ファイルハッシュ", text: $fileHash)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct SearchProjectSection: View {
    @Binding var selectedProjectId: UUID?
    let projects: [PPProject]

    var body: some View {
        Section("プロジェクト") {
            Picker(
                "対象",
                selection: Binding(
                    get: { selectedProjectId?.uuidString ?? "all" },
                    set: { selectedProjectId = $0 == "all" ? nil : UUID(uuidString: $0) }
                )
            ) {
                Text("指定なし").tag("all")
                ForEach(projects.filter { $0.isArchived != true }.sorted { $0.name < $1.name }, id: \.id) { project in
                    Text(project.name).tag(project.id.uuidString)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

private enum SearchFilterDateBuilder {
    static func makeRange(
        useStart: Bool,
        startDate: Date,
        useEnd: Bool,
        endDate: Date
    ) -> ClosedRange<Date>? {
        let calendar = Calendar.current
        let lowerBound = useStart ? calendar.startOfDay(for: startDate) : nil
        let upperBound = useEnd
            ? (calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: endDate)) ?? endDate)
            : nil

        switch (lowerBound, upperBound) {
        case let (lower?, upper?):
            return min(lower, upper)...max(lower, upper)
        case let (lower?, nil):
            return lower...Date.distantFuture
        case let (nil, upper?):
            return Date.distantPast...upper
        case (nil, nil):
            return nil
        }
    }
}

private enum SearchFilterDecimalBuilder {
    static func makeRange(minimumText: String, maximumText: String) -> ClosedRange<Decimal>? {
        let minimum = decimal(from: minimumText)
        let maximum = decimal(from: maximumText)

        switch (minimum, maximum) {
        case let (min?, max?):
            return Swift.min(min, max)...Swift.max(min, max)
        case let (min?, nil):
            return min...Decimal(string: "999999999999999999")!
        case let (nil, max?):
            return Decimal.zero...max
        case (nil, nil):
            return nil
        }
    }

    private static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
