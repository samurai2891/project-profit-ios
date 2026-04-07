#!/usr/bin/env python3

from pathlib import Path

from xlsx_parity import compare_snapshots, inspect_workbook, load_snapshot


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "golden_xlsx" / "templates"
LEDGERS = {
    "cash_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_cash_book_template.xlsx",
    "cash_book_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_cash_book_invoice_template.xlsx",
    "bank_account_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_bank_account_book_template.xlsx",
    "bank_account_book_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_bank_account_book_invoice_template.xlsx",
    "accounts_receivable_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_accounts_receivable_template.xlsx",
    "accounts_payable_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_accounts_payable_template.xlsx",
    "expense_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_expense_book_template.xlsx",
    "expense_book_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_expense_book_invoice_template.xlsx",
    "general_ledger": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_general_ledger_template.xlsx",
    "general_ledger_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_general_ledger_invoice_template.xlsx",
    "journal": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_journal_template.xlsx",
    "white_tax_bookkeeping": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_white_tax_bookkeeping_template.xlsx",
    "white_tax_bookkeeping_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_white_tax_bookkeeping_invoice_template.xlsx",
    "transportation_expense": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_transportation_expense_template.xlsx",
    "fixed_asset_register": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_fixed_asset_register_template.xlsx",
    "fixed_asset_depreciation": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_fixed_asset_depreciation_template.xlsx",
}


def verify(key: str) -> list[str]:
    actual = inspect_workbook(LEDGERS[key])
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
