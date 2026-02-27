import SwiftUI

// MARK: - Editable Line Item

struct EditableLineItem: Identifiable {
    let id: UUID
    var name: String
    var quantity: Int
    var unitPrice: Int

    var subtotal: Int { quantity * unitPrice }

    init(id: UUID = UUID(), name: String = "", quantity: Int = 1, unitPrice: Int = 0) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    init(from lineItem: LineItem) {
        self.id = UUID()
        self.name = lineItem.name
        self.quantity = lineItem.quantity
        self.unitPrice = lineItem.unitPrice
    }

    func toLineItem() -> LineItem {
        LineItem(name: name, quantity: quantity, unitPrice: unitPrice)
    }

    func toReceiptLineItem() -> ReceiptLineItem {
        ReceiptLineItem(name: name, quantity: quantity, unitPrice: unitPrice)
    }
}

// MARK: - LineItemsEditView

struct LineItemsEditView: View {
    @Binding var items: [EditableLineItem]

    private var total: Int {
        items.reduce(0) { $0 + $1.subtotal }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("明細")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if !items.isEmpty {
                    Text("合計: \(formatCurrency(total))")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                emptyState
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                    lineItemRow(index: index)
                }
            }

            addButton
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("明細なし")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            Spacer()
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Line Item Row

    private func lineItemRow(index: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                TextField("品目名", text: $items[index].name)
                    .font(.subheadline)
                    .accessibilityLabel("品目名")

                Spacer()

                Button {
                    items.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.error.opacity(0.7))
                        .font(.subheadline)
                }
                .accessibilityLabel("品目を削除")
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("数量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("1", text: Binding(
                        get: { String(items[index].quantity) },
                        set: { items[index].quantity = max(1, Int($0) ?? 1) }
                    ))
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.border))
                    .accessibilityLabel("数量")
                }

                HStack(spacing: 4) {
                    Text("単価")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("¥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", text: Binding(
                        get: { String(items[index].unitPrice) },
                        set: { items[index].unitPrice = max(0, Int($0) ?? 0) }
                    ))
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .font(.subheadline)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.border))
                    .accessibilityLabel("単価")
                }

                Spacer()

                Text(formatCurrency(items[index].subtotal))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("小計 \(formatCurrency(items[index].subtotal))")
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            items.append(EditableLineItem())
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("品目を追加")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .accessibilityLabel("品目を追加")
    }
}
