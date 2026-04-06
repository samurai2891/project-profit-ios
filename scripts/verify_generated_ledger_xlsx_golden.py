#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path("/Users/yutaro/project-profit-ios")
INSPECTOR = ROOT / "scripts" / "inspect_xlsx_layout.py"
GENERATED = ROOT / ".golden-generated-ledger-xlsx"
PADDING = 0.7109375

EXPECTATIONS = {
    "cash_book": {"sheet_name": "現金出納帳", "rows": {1: ["現　金　出　納　帳"], 3: ["月", "日", "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 12.0}},
    "cash_book_invoice": {"sheet_name": "現金出納帳（インボイス）", "rows": {1: ["現　金　出　納　帳"], 3: ["月", "日", "摘　　　　要", "勘 定 科 目", "軽減税率", "インボイス", "入　　金", "出　　金", "残   高"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 8.0, "F": 10.0, "G": 12.0, "H": 12.0, "I": 12.0}},
    "bank_account_book": {"sheet_name": "預金出納帳", "rows": {1: ["預　金　出　納　帳"], 7: ["月", "日", "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 12.0}},
    "bank_account_book_invoice": {"sheet_name": "預金出納帳（インボイス）", "rows": {1: ["預　金　出　納　帳"], 7: ["月", "日", "摘　　　　要", "勘 定 科 目", "軽減税率", "インボイス", "入　　金", "出　　金", "残   高"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 8.0, "F": 10.0, "G": 12.0, "H": 12.0, "I": 12.0}},
    "accounts_receivable_book": {"sheet_name": "売掛帳", "rows": {1: ["売掛帳"], 8: ["月", "日", "相手科目", "摘要", "数量", "単価", "売上金額", "入金金額", "売掛金残高"]}, "widths": {"A": 7.0, "B": 7.0, "C": 16.0, "D": 24.0, "E": 10.0, "F": 12.0, "G": 14.0, "H": 14.0, "I": 16.0}},
    "accounts_payable_book": {"sheet_name": "買掛帳", "rows": {1: ["買掛帳"], 8: ["月", "日", "相手科目", "摘要", "数量", "単価", "仕入金額", "支払金額", "買掛金残高"]}, "widths": {"A": 7.0, "B": 7.0, "C": 16.0, "D": 24.0, "E": 10.0, "F": 12.0, "G": 14.0, "H": 14.0, "I": 16.0}},
    "expense_book": {"sheet_name": "経費帳", "rows": {1: ["経　　　費　　　帳"], 8: ["月", "日", "相手科目", "摘要", "金額", "金額合計"]}, "widths": {"A": 7.0, "B": 7.0, "C": 18.0, "D": 28.0, "E": 14.0, "F": 14.0}},
    "expense_book_invoice": {"sheet_name": "経費帳（インボイス）", "rows": {1: ["経　　　費　　　帳"], 8: ["月", "日", "相手科目", "摘要", "軽減税率", "インボイス", "金額", "累計"]}, "widths": {"A": 7.0, "B": 7.0, "C": 18.0, "D": 24.0, "E": 12.0, "F": 14.0, "G": 14.0, "H": 14.0}},
    "general_ledger": {"sheet_name": "総勘定元帳", "rows": {1: ["総　勘　定　元　帳"], 9: ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"]}, "widths": {"A": 8.0, "B": 8.0, "C": 18.0, "D": 26.0, "E": 14.0, "F": 14.0, "G": 16.0}},
    "general_ledger_invoice": {"sheet_name": "総勘定元帳（インボイス）", "rows": {1: ["総　勘　定　元　帳"], 9: ["月", "日", "相手科目", "摘要", "軽減税率", "インボイス", "借方", "貸方", "差引残高"]}, "widths": {"A": 8.0, "B": 8.0, "C": 16.0, "D": 22.0, "E": 12.0, "F": 14.0, "G": 14.0, "H": 14.0, "I": 16.0}},
    "journal": {"sheet_name": "仕訳帳", "rows": {1: ["仕　　訳　　帳"], 8: ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"]}, "widths": {"A": 7.0, "B": 7.0, "C": 18.0, "D": 14.0, "E": 18.0, "F": 14.0, "G": 28.0}},
    "white_tax_bookkeeping": {"sheet_name": "白色申告用 簡易帳簿", "rows": {1: ["白色申告用 簡易帳簿"], 8: ["月", "日", "摘要", "売上金額", "雑収入等", "仕入", "給料賃金", "外注工賃", "減価償却費", "貸倒金"]}, "widths": {"A": 7.0, "B": 7.0, "C": 24.0, "D": 12.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.0, "I": 12.0, "J": 12.0}},
    "white_tax_bookkeeping_invoice": {"sheet_name": "白色申告用 簡易帳簿（インボイス）", "rows": {1: ["白色申告用 簡易帳簿"], 8: ["月", "日", "摘要", "軽減税率", "インボイス", "売上金額", "雑収入等", "仕入", "給料賃金", "外注工賃"]}, "widths": {"A": 7.0, "B": 7.0, "C": 22.0, "D": 10.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.0, "I": 12.0, "J": 12.0}},
    "transportation_expense": {"sheet_name": "交通費精算書", "rows": {1: ["交通費精算書"], 12: ["日付", "行先", "目的", "交通機関", "区間（起点）", "区間（終点）", "片/往", "金額"]}, "widths": {"A": 12.0, "B": 18.0, "C": 18.0, "D": 14.0, "E": 14.0, "F": 14.0, "G": 10.0, "H": 12.0}},
    "fixed_asset_register": {"sheet_name": "固定資産台帳", "rows": {1: ["固　定　資　産　台　帳"], 9: ["取得年月日"], 10: ["所在"], 11: ["耐用年数"], 12: ["償却方法"], 13: ["償却率"]}, "widths": {"A": 12.0, "B": 24.0, "C": 10.0, "D": 12.0, "E": 14.0, "F": 14.0, "G": 10.0, "H": 14.0, "I": 10.0, "J": 14.0}},
    "fixed_asset_depreciation": {"sheet_name": "固定資産台帳 兼 減価償却計算表", "rows": {1: ["固定資産台帳 兼 減価償却計算表"], 8: ["勘定科目", "資産コード", "資産名", "資産の種類", "状態", "数量", "取得日", "取得価額", "償却方法", "耐用年数"]}, "widths": {"A": 14.0, "B": 12.0, "C": 18.0, "D": 14.0, "E": 10.0, "F": 8.0, "G": 12.0, "H": 14.0, "I": 12.0, "J": 10.0}},
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
    path = GENERATED / f"{key}.xlsx"
    if not path.exists():
        return [f"{key}: missing generated workbook at {path}"]
    snapshot = inspect(path)
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
            continue
        normalized = actual_width - PADDING
        if abs(normalized - expected_width) > 0.05:
            errors.append(f"{key}: column {column} expected width {expected_width} but got {actual_width} (normalized {normalized})")
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
