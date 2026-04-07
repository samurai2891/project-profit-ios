#!/usr/bin/env python3

from pathlib import Path

from xlsx_parity import inspect_workbook, write_snapshot


ROOT = Path(__file__).resolve().parent.parent

TEMPLATE_TARGETS = {
    "ledger__cash_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_cash_book_template.xlsx",
    "ledger__cash_book_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_cash_book_invoice_template.xlsx",
    "ledger__bank_account_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_bank_account_book_template.xlsx",
    "ledger__bank_account_book_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_bank_account_book_invoice_template.xlsx",
    "ledger__accounts_receivable_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_accounts_receivable_template.xlsx",
    "ledger__accounts_payable_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_accounts_payable_template.xlsx",
    "ledger__expense_book": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_expense_book_template.xlsx",
    "ledger__expense_book_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_expense_book_invoice_template.xlsx",
    "ledger__general_ledger": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_general_ledger_template.xlsx",
    "ledger__general_ledger_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_general_ledger_invoice_template.xlsx",
    "ledger__journal": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_journal_template.xlsx",
    "ledger__white_tax_bookkeeping": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_white_tax_bookkeeping_template.xlsx",
    "ledger__white_tax_bookkeeping_invoice": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_white_tax_bookkeeping_invoice_template.xlsx",
    "ledger__transportation_expense": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_transportation_expense_template.xlsx",
    "ledger__fixed_asset_register": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_fixed_asset_register_template.xlsx",
    "ledger__fixed_asset_depreciation": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_fixed_asset_depreciation_template.xlsx",
    "report__profit_loss": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/reports/project-profit-ios_profit_loss_template.xlsx",
    "report__balance_sheet": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/reports/project-profit-ios_balance_sheet_template.xlsx",
    "report__trial_balance": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_trial_balance_template.xlsx",
    "report__journal": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_journal_template.xlsx",
    "report__general_ledger": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_general_ledger_template.xlsx",
    "report__fixed_assets": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_fixed_asset_depreciation_template.xlsx",
}

GENERATED_TARGETS = {
    "ledger__cash_book": ROOT / ".golden-generated-ledger-xlsx/cash_book.xlsx",
    "ledger__cash_book_invoice": ROOT / ".golden-generated-ledger-xlsx/cash_book_invoice.xlsx",
    "ledger__bank_account_book": ROOT / ".golden-generated-ledger-xlsx/bank_account_book.xlsx",
    "ledger__bank_account_book_invoice": ROOT / ".golden-generated-ledger-xlsx/bank_account_book_invoice.xlsx",
    "ledger__accounts_receivable_book": ROOT / ".golden-generated-ledger-xlsx/accounts_receivable_book.xlsx",
    "ledger__accounts_payable_book": ROOT / ".golden-generated-ledger-xlsx/accounts_payable_book.xlsx",
    "ledger__expense_book": ROOT / ".golden-generated-ledger-xlsx/expense_book.xlsx",
    "ledger__expense_book_invoice": ROOT / ".golden-generated-ledger-xlsx/expense_book_invoice.xlsx",
    "ledger__general_ledger": ROOT / ".golden-generated-ledger-xlsx/general_ledger.xlsx",
    "ledger__general_ledger_invoice": ROOT / ".golden-generated-ledger-xlsx/general_ledger_invoice.xlsx",
    "ledger__journal": ROOT / ".golden-generated-ledger-xlsx/journal.xlsx",
    "ledger__white_tax_bookkeeping": ROOT / ".golden-generated-ledger-xlsx/white_tax_bookkeeping.xlsx",
    "ledger__white_tax_bookkeeping_invoice": ROOT / ".golden-generated-ledger-xlsx/white_tax_bookkeeping_invoice.xlsx",
    "ledger__transportation_expense": ROOT / ".golden-generated-ledger-xlsx/transportation_expense.xlsx",
    "ledger__fixed_asset_register": ROOT / ".golden-generated-ledger-xlsx/fixed_asset_register.xlsx",
    "ledger__fixed_asset_depreciation": ROOT / ".golden-generated-ledger-xlsx/fixed_asset_depreciation.xlsx",
    "report__profit_loss": ROOT / ".golden-generated-xlsx/profit_loss.xlsx",
    "report__balance_sheet": ROOT / ".golden-generated-xlsx/balance_sheet.xlsx",
    "report__trial_balance": ROOT / ".golden-generated-xlsx/trial_balance.xlsx",
    "report__journal": ROOT / ".golden-generated-xlsx/journal.xlsx",
    "report__ledger": ROOT / ".golden-generated-xlsx/ledger.xlsx",
    "report__fixed_assets": ROOT / ".golden-generated-xlsx/fixed_assets.xlsx",
}


def main() -> int:
    templates_dir = ROOT / "scripts/golden_xlsx/templates"
    generated_dir = ROOT / "scripts/golden_xlsx/generated"

    for key, workbook in TEMPLATE_TARGETS.items():
        write_snapshot(templates_dir / f"{key}.json", inspect_workbook(workbook))
        print(f"WROTE templates/{key}.json")

    for key, workbook in GENERATED_TARGETS.items():
        write_snapshot(
            generated_dir / f"{key}.json",
            inspect_workbook(workbook, width_padding=0.7109375),
        )
        print(f"WROTE generated/{key}.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
