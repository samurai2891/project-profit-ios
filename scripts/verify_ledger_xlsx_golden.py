#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path("/Users/yutaro/project-profit-ios")
INSPECTOR = ROOT / "scripts" / "inspect_xlsx_layout.py"
LEDGERS = ROOT / "ProjectProfit" / "Ledger" / "Resources" / "excel_templates" / "ledgers"

EXPECTATIONS = {
    "cash_book": {
        "path": LEDGERS / "project-profit-ios_cash_book_template.xlsx",
        "sheet_name": "L01_CashStd_Form",
        "rows": {1: ["現金出納帳（通常版）"], 4: ["帳簿名", "現金出納帳"], 9: ["月", "日", "摘要", "勘定科目", "入金", "出金", "残高"]},
        "widths": {"A": 8.0, "B": 8.0, "C": 28.0, "D": 18.0, "E": 14.0, "F": 14.0, "G": 14.0},
    },
    "cash_book_invoice": {
        "path": LEDGERS / "project-profit-ios_cash_book_invoice_template.xlsx",
        "sheet_name": "L02_CashInv_Form",
        "rows": {1: ["現金出納帳（インボイス版）"], 4: ["帳簿名", "現金出納帳（インボイス）"], 9: ["月", "日", "摘要", "勘定科目", "軽減税率", "インボイス区分", "入金", "出金", "残高"]},
        "widths": {"A": 8.0, "B": 8.0, "C": 24.0, "D": 16.0, "E": 12.0, "F": 14.0, "G": 14.0, "H": 14.0, "I": 14.0},
    },
    "bank_account_book": {
        "path": LEDGERS / "project-profit-ios_bank_account_book_template.xlsx",
        "sheet_name": "L03_BankStd_Form",
        "rows": {1: ["預金出納帳（通常版）"], 4: ["帳簿名", "預金出納帳"], 8: ["口座種類", "普通"], 9: ["前期より繰越", 0]},
        "widths": {"A": 8.0, "B": 8.0, "C": 28.0, "D": 18.0, "E": 14.0, "F": 14.0, "G": 14.0, "H": 13.0},
    },
    "bank_account_book_invoice": {
        "path": LEDGERS / "project-profit-ios_bank_account_book_invoice_template.xlsx",
        "sheet_name": "L04_BankInv_Form",
        "rows": {1: ["預金出納帳（インボイス版）"], 4: ["帳簿名", "預金出納帳（インボイス）"], 9: ["前期より繰越", 0]},
        "widths": {"A": 8.0, "B": 8.0, "C": 24.0, "D": 16.0, "E": 12.0, "F": 14.0, "G": 14.0, "H": 14.0, "I": 14.0},
    },
    "accounts_receivable_book": {
        "path": LEDGERS / "project-profit-ios_accounts_receivable_template.xlsx",
        "sheet_name": "L11_AR_Form",
        "rows": {1: ["売掛帳"], 4: ["帳簿名", "売掛帳"], 9: ["月", "日", "相手科目", "摘要", "数量", "単価", "売上金額", "入金金額", "売掛金残高"]},
        "widths": {"A": 7.0, "B": 7.0, "C": 16.0, "D": 24.0, "E": 10.0, "F": 12.0, "G": 14.0, "H": 14.0, "I": 16.0},
    },
    "accounts_payable_book": {
        "path": LEDGERS / "project-profit-ios_accounts_payable_template.xlsx",
        "sheet_name": "L12_AP_Form",
        "rows": {1: ["買掛帳"], 4: ["帳簿名", "買掛帳"], 9: ["月", "日", "相手科目", "摘要", "数量", "単価", "仕入金額", "支払金額", "買掛金残高"]},
        "widths": {"A": 7.0, "B": 7.0, "C": 16.0, "D": 24.0, "E": 10.0, "F": 12.0, "G": 14.0, "H": 14.0, "I": 16.0},
    },
    "expense_book": {
        "path": LEDGERS / "project-profit-ios_expense_book_template.xlsx",
        "sheet_name": "L05_ExpStd_Form",
        "rows": {1: ["経費帳（通常版）"], 4: ["帳簿名", "経費帳"], 9: ["月", "日", "相手科目", "摘要", "金額", "金額合計"]},
        "widths": {"A": 8.0, "B": 8.0, "C": 18.0, "D": 28.0, "E": 14.0, "F": 14.0},
    },
    "expense_book_invoice": {
        "path": LEDGERS / "project-profit-ios_expense_book_invoice_template.xlsx",
        "sheet_name": "L06_ExpInv_Form",
        "rows": {1: ["経費帳（インボイス版）"], 4: ["帳簿名", "経費帳（インボイス）"], 9: ["月", "日", "相手科目", "摘要", "軽減税率", "インボイス区分", "金額", "金額合計"]},
        "widths": {"A": 8.0, "B": 8.0, "C": 16.0, "D": 24.0, "E": 12.0, "F": 14.0, "G": 14.0, "H": 14.0},
    },
    "general_ledger": {
        "path": LEDGERS / "project-profit-ios_general_ledger_template.xlsx",
        "sheet_name": "L07_GLedStd_Form",
        "rows": {1: ["総勘定元帳（通常版）"], 4: ["帳簿名", "総勘定元帳"], 10: ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"]},
        "widths": {"A": 8.0, "B": 8.0, "C": 18.0, "D": 26.0, "E": 14.0, "F": 14.0, "G": 16.0},
    },
    "general_ledger_invoice": {
        "path": LEDGERS / "project-profit-ios_general_ledger_invoice_template.xlsx",
        "sheet_name": "L08_GLedInv_Form",
        "rows": {1: ["総勘定元帳（インボイス版）"], 4: ["帳簿名", "総勘定元帳（インボイス）"], 10: ["月", "日", "相手科目", "摘要", "軽減税率", "インボイス区分", "借方", "貸方", "差引残高"]},
        "widths": {"A": 8.0, "B": 8.0, "C": 16.0, "D": 22.0, "E": 12.0, "F": 14.0, "G": 14.0, "H": 14.0, "I": 16.0},
    },
    "journal": {
        "path": LEDGERS / "project-profit-ios_journal_template.xlsx",
        "sheet_name": "L13_Journal_Form",
        "rows": {1: ["仕訳帳"], 4: ["帳簿名", "仕訳帳"], 9: ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"]},
        "widths": {"A": 7.0, "B": 7.0, "C": 18.0, "D": 14.0, "E": 18.0, "F": 14.0, "G": 28.0},
    },
    "white_tax_bookkeeping": {
        "path": LEDGERS / "project-profit-ios_white_tax_bookkeeping_template.xlsx",
        "sheet_name": "L09_WhiteStd_Form",
        "rows": {1: ["白色申告用 簡易帳簿（通常版）"], 4: ["帳簿名", "白色申告用 簡易帳簿"], 9: ["月", "日", "摘要", "売上金額", "雑収入等", "仕入", "給料賃金", "外注工賃", "減価償却費", "貸倒金"]},
        "widths": {"A": 7.0, "B": 7.0, "C": 24.0, "D": 12.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.0, "I": 12.0, "J": 12.0},
    },
    "white_tax_bookkeeping_invoice": {
        "path": LEDGERS / "project-profit-ios_white_tax_bookkeeping_invoice_template.xlsx",
        "sheet_name": "L10_WhiteInv_Form",
        "rows": {1: ["白色申告用 簡易帳簿（インボイス版）"], 4: ["帳簿名", "白色申告用 簡易帳簿（インボイス）"], 9: ["月", "日", "摘要", "軽減税率", "インボイス区分", "売上金額", "雑収入等", "仕入", "給料賃金", "外注工賃"]},
        "widths": {"A": 7.0, "B": 7.0, "C": 22.0, "D": 10.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.0, "I": 12.0, "J": 12.0},
    },
    "transportation_expense": {
        "path": LEDGERS / "project-profit-ios_transportation_expense_template.xlsx",
        "sheet_name": "L16_Travel_Form",
        "rows": {1: ["交通費精算書"], 4: ["帳票名", "交通費精算書"], 12: ["日付", "行先", "目的", "交通機関", "区間（起点）", "区間（終点）", "片/往", "金額"]},
        "widths": {"A": 12.0, "B": 18.0, "C": 18.0, "D": 14.0, "E": 14.0, "F": 14.0, "G": 10.0, "H": 12.0},
    },
    "fixed_asset_register": {
        "path": LEDGERS / "project-profit-ios_fixed_asset_register_template.xlsx",
        "sheet_name": "L14_FixReg_Form",
        "rows": {1: ["固定資産台帳"], 4: ["帳簿名", "固定資産台帳"], 9: ["取得年月日"], 10: ["所在"], 11: ["耐用年数"], 12: ["償却方法"], 13: ["償却率"]},
        "widths": {"A": 12.0, "B": 24.0, "C": 10.0, "D": 12.0, "E": 14.0, "F": 14.0, "G": 10.0, "H": 14.0, "I": 10.0, "J": 14.0},
    },
    "fixed_asset_depreciation": {
        "path": LEDGERS / "project-profit-ios_fixed_asset_depreciation_template.xlsx",
        "sheet_name": "L15_FixDep_Form",
        "rows": {1: ["固定資産台帳 兼 減価償却計算表"], 4: ["帳簿名", "固定資産台帳 兼 減価償却計算表"], 9: ["勘定科目", "資産コード", "資産名", "資産の種類", "状態", "数量", "取得日", "取得価額", "償却方法", "耐用年数"]},
        "widths": {"A": 14.0, "B": 12.0, "C": 18.0, "D": 14.0, "E": 10.0, "F": 8.0, "G": 12.0, "H": 14.0, "I": 12.0, "J": 10.0},
    },
}


def inspect(path: Path) -> dict:
    result = subprocess.run([sys.executable, str(INSPECTOR), str(path)], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"inspect failed: {path}")
    return json.loads(result.stdout)


def compare_row(actual_row, expected_row, key, row_number):
    errors = []
    for index, expected in enumerate(expected_row):
        actual = actual_row[index] if index < len(actual_row) else None
        if actual != expected:
            errors.append(f"{key}: row {row_number} col {index + 1} expected {expected!r} but got {actual!r}")
    return errors


def verify(key):
    spec = EXPECTATIONS[key]
    snapshot = inspect(spec["path"])
    errors = []
    if snapshot["sheet_name"] != spec["sheet_name"]:
        errors.append(f"{key}: expected sheet {spec['sheet_name']!r} but got {snapshot['sheet_name']!r}")
    for row_number, expected_row in spec["rows"].items():
        actual_row = snapshot["rows"].get(str(row_number), [])
        errors.extend(compare_row(actual_row, expected_row, key, row_number))
    for column, expected_width in spec["widths"].items():
        actual_width = snapshot["widths"].get(column)
        if actual_width is None:
            errors.append(f"{key}: missing width for column {column}")
        elif abs(actual_width - expected_width) > 0.01:
            errors.append(f"{key}: column {column} expected width {expected_width} but got {actual_width}")
    return errors


def main():
    errors = []
    for key in EXPECTATIONS:
        result = verify(key)
        if result:
            errors.extend(result)
        else:
            print(f"PASS {key}")
    if errors:
        for error in errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
