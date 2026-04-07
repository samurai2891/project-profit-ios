#!/usr/bin/env python3

from pathlib import Path

from xlsx_parity import compare_snapshots, inspect_workbook, load_snapshot


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "golden_xlsx" / "generated"
GENERATED = ROOT / ".golden-generated-ledger-xlsx"
WIDTH_PADDING = 0.7109375
LEDGERS = {
    "cash_book": GENERATED / "cash_book.xlsx",
    "cash_book_invoice": GENERATED / "cash_book_invoice.xlsx",
    "bank_account_book": GENERATED / "bank_account_book.xlsx",
    "bank_account_book_invoice": GENERATED / "bank_account_book_invoice.xlsx",
    "accounts_receivable_book": GENERATED / "accounts_receivable_book.xlsx",
    "accounts_payable_book": GENERATED / "accounts_payable_book.xlsx",
    "expense_book": GENERATED / "expense_book.xlsx",
    "expense_book_invoice": GENERATED / "expense_book_invoice.xlsx",
    "general_ledger": GENERATED / "general_ledger.xlsx",
    "general_ledger_invoice": GENERATED / "general_ledger_invoice.xlsx",
    "journal": GENERATED / "journal.xlsx",
    "white_tax_bookkeeping": GENERATED / "white_tax_bookkeeping.xlsx",
    "white_tax_bookkeeping_invoice": GENERATED / "white_tax_bookkeeping_invoice.xlsx",
    "transportation_expense": GENERATED / "transportation_expense.xlsx",
    "fixed_asset_register": GENERATED / "fixed_asset_register.xlsx",
    "fixed_asset_depreciation": GENERATED / "fixed_asset_depreciation.xlsx",
}


def verify(key: str) -> list[str]:
    path = LEDGERS[key]
    if not path.exists():
        return [f"{key}: missing generated workbook at {path}"]
    actual = inspect_workbook(path, width_padding=WIDTH_PADDING)
    expected = load_snapshot(FIXTURES / f"ledger__{key}.json")
    return compare_snapshots(key, actual, expected)


def main() -> int:
    errors: list[str] = []
    for key in LEDGERS:
        result = verify(key)
        if result:
            errors.extend(result)
        else:
            print(f"PASS {key}")

    if errors:
        for error in errors:
            print(f"FAIL {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
