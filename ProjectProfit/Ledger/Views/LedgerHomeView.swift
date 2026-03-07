// ============================================================
// LedgerHomeView.swift
// 帳簿一覧画面 - 全帳簿の一覧表示と新規作成
// ============================================================

import SwiftUI

struct LedgerHomeView: View {
    @Environment(LedgerDataStore.self) private var ledgerStore

    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if ledgerStore.books.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .navigationTitle("台帳管理")
        .toolbar {
            if !ledgerStore.isReadOnly {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("台帳を追加")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NavigationStack {
                LedgerBookCreateView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("帳簿がありません")
                .font(.headline)
            Text(ledgerStore.isReadOnly ? "旧台帳は読み取り専用です" : "＋ボタンから帳簿を追加してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bookList: some View {
        List {
            if ledgerStore.isReadOnly {
                ForEach(ledgerStore.books, id: \.id) { book in
                    NavigationLink(destination: LedgerBookDetailView(bookId: book.id)) {
                        bookRow(book)
                    }
                }
            } else {
                ForEach(ledgerStore.books, id: \.id) { book in
                    NavigationLink(destination: LedgerBookDetailView(bookId: book.id)) {
                        bookRow(book)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let book = ledgerStore.books[index]
                        ledgerStore.deleteBook(book.id)
                    }
                }
            }
        }
    }

    private func bookRow(_ book: SDLedgerBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if book.includeInvoice {
                    Text("インボイス")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.primary.opacity(0.15))
                        .foregroundStyle(AppColors.primary)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text(book.ledgerType?.displayName ?? "不明")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                let balance = ledgerStore.finalBalance(for: book.id)
                if let balance {
                    Text("残高: \(formatCurrency(balance))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("更新: \(book.updatedAt, format: .dateTime.month().day().hour().minute())")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
