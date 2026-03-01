// ============================================================
// LedgerAccountPicker.swift
// 台帳タイプ別の勘定科目選択Picker
// ============================================================

import SwiftUI

struct LedgerAccountPicker: View {
    let label: String
    @Binding var selection: String
    let ledgerType: LedgerType

    @State private var showPicker = false
    @State private var searchText = ""

    private var availableAccounts: [AccountItem] {
        let all = AccountMaster.all
        switch ledgerType {
        case .accountsReceivable:
            let names: Set<String> = [
                "現金", "普通預金", "受取手形", "事業主貸",
                "支払手形", "買掛金", "売上高"
            ]
            return all.filter { names.contains($0.name) }
        case .accountsPayable:
            let names: Set<String> = [
                "現金", "普通預金", "受取手形",
                "支払手形", "買掛金", "事業主借", "仕入高"
            ]
            return all.filter { names.contains($0.name) }
        case .expenseBook, .expenseBookInvoice:
            let names: Set<String> = [
                "現金", "普通預金", "未払金", "事業主借"
            ]
            return all.filter { names.contains($0.name) }
        default:
            return all
        }
    }

    private var filteredAccounts: [AccountItem] {
        if searchText.isEmpty {
            return availableAccounts
        }
        return availableAccounts.filter { $0.name.contains(searchText) }
    }

    private var groupedAccounts: [(AccountCategory, [AccountItem])] {
        let grouped = Dictionary(grouping: filteredAccounts) { $0.category }
        return AccountCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(selection.isEmpty ? "選択してください" : selection)
                    .foregroundStyle(selection.isEmpty ? .tertiary : .primary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List {
                    ForEach(groupedAccounts, id: \.0) { category, items in
                        Section(category.rawValue) {
                            ForEach(items) { item in
                                Button {
                                    selection = item.name
                                    showPicker = false
                                } label: {
                                    HStack {
                                        Text(item.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if item.name == selection {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "科目を検索")
                .navigationTitle("勘定科目")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { showPicker = false }
                    }
                    if !selection.isEmpty {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("クリア") {
                                selection = ""
                                showPicker = false
                            }
                        }
                    }
                }
            }
        }
    }
}
