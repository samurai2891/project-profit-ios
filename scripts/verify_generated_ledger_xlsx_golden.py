#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
INSPECTOR = ROOT / "scripts" / "inspect_xlsx_layout.py"
GENERATED = ROOT / ".golden-generated-ledger-xlsx"
PADDING = 0.7109375

EXPECTATIONS = {
    "cash_book": {"sheet_name": "現金出納帳", "rows": {1: ["現　金　出　納　帳"], 3: ["日付", None, "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"], 4: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 12.0}},
    "cash_book_invoice": {"sheet_name": "現金出納帳", "rows": {1: ["現　金　出　納　帳"], 3: ["日付", None, "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"], 4: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 12.0}},
    "bank_account_book": {"sheet_name": "預金出納帳", "rows": {1: ["預　金　出　納　帳"], 2: ["銀行名", None, "テスト銀行"], 4: ["口座種類", None, "普通"], 7: ["日付", None, "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"], 8: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.289}},
    "bank_account_book_invoice": {"sheet_name": "預金出納帳", "rows": {1: ["預　金　出　納　帳"], 2: ["銀行名", None, "テスト銀行"], 4: ["口座種類", None, "普通"], 7: ["日付", None, "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"], 8: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 28.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.289}},
    "accounts_receivable_book": {"sheet_name": "売掛帳", "rows": {1: ["売　掛　帳"], 2: ["得意先名", None, None, "得意先A"], 4: ["日付", None, "相手科目", "摘　　　　要", "数量", "単価", "売上金額", "入金金額", "売掛金残高"], 5: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 12.0, "D": 24.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.0, "I": 12.0}},
    "accounts_payable_book": {"sheet_name": "買掛帳", "rows": {1: ["買　掛　帳"], 2: ["仕入先名", None, None, "仕入先A"], 4: ["日付", None, "相手科目", "摘　　　　要", "数量", "単価", "仕入金額", "支払金額", "買掛金残高"], 5: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 12.0, "D": 24.0, "E": 12.0, "F": 12.0, "G": 12.0, "H": 12.0, "I": 12.0}},
    "expense_book": {"sheet_name": "経費帳", "rows": {1: ["経　費　帳"], 2: ["勘定科目名", None, "消耗品費"], 3: ["日付", None, "相手科目", "摘　　　　要", "金額", "累計"], 4: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 14.0, "D": 28.0, "E": 12.0, "F": 12.0}},
    "expense_book_invoice": {"sheet_name": "経費帳", "rows": {1: ["経　費　帳"], 2: ["勘定科目名", None, "消耗品費"], 3: ["日付", None, "相手科目", "摘　　　　要", "金額", "累計"], 4: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 14.0, "D": 28.0, "E": 12.0, "F": 12.0}},
    "general_ledger": {"sheet_name": "総勘定元帳", "rows": {1: [None, None, None, None, None, "科目の属性：", "資産"], 2: ["総勘定元帳"], 3: ["勘定科目", None, None, "現金"], 5: ["日付", None, "相手科目", "摘　　　　要", "借方", "貸方", "差引残高"], 6: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 14.0, "D": 28.0, "E": 12.0, "F": 12.0, "G": 12.0}},
    "general_ledger_invoice": {"sheet_name": "総勘定元帳", "rows": {1: [None, None, None, None, None, "科目の属性：", "資産"], 2: ["総勘定元帳"], 3: ["勘定科目", None, None, "現金"], 5: ["日付", None, "相手科目", "摘　　　　要", "借方", "貸方", "差引残高"], 6: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 14.0, "D": 28.0, "E": 12.0, "F": 12.0, "G": 12.0}},
    "journal": {"sheet_name": "仕訳帳", "rows": {1: ["仕　訳　帳"], 3: ["日付", None, "借方科目", "借方金額", "貸方科目", "貸方金額", "摘　　　　要"], 4: ["月", "日"]}, "widths": {"A": 4.0, "B": 4.0, "C": 14.0, "D": 12.0, "E": 14.0, "F": 12.0, "G": 28.0}},
    "white_tax_bookkeeping": {"sheet_name": "白色申告用 簡易帳簿", "rows": {1: ["白色申告用簡易帳簿"], 2: ["年分", "2025年"], 3: ["月", "日", "摘要", "売上金額", "雑収入等", "仕入", "給料賃金", "外注工賃", "減価償却費", "貸倒金"]}, "widths": {"A": 4.0, "B": 4.0, "C": 18.0, "D": 10.0, "E": 10.0, "F": 10.0, "G": 10.0, "H": 10.0, "I": 10.0, "J": 10.0, "K": 10.0, "L": 10.0, "M": 10.0, "N": 10.0, "O": 10.0, "P": 10.0, "Q": 10.0, "R": 10.0, "S": 10.0, "T": 10.0, "U": 10.0, "V": 10.0, "W": 10.0, "X": 10.0}},
    "white_tax_bookkeeping_invoice": {"sheet_name": "白色申告用 簡易帳簿", "rows": {1: ["白色申告用簡易帳簿"], 2: ["年分", "2025年"], 3: ["月", "日", "摘要", "売上金額", "雑収入等", "仕入", "給料賃金", "外注工賃", "減価償却費", "貸倒金"]}, "widths": {"A": 4.0, "B": 4.0, "C": 18.0, "D": 10.0, "E": 10.0, "F": 10.0, "G": 10.0, "H": 10.0, "I": 10.0, "J": 10.0, "K": 10.0, "L": 10.0, "M": 10.0, "N": 10.0, "O": 10.0, "P": 10.0, "Q": 10.0, "R": 10.0, "S": 10.0, "T": 10.0, "U": 10.0, "V": 10.0, "W": 10.0, "X": 10.0}},
    "transportation_expense": {"sheet_name": "交通費精算書", "rows": {1: ["交通費精算書"], 2: ["所属", "営業部", None, "氏名", "田中", None, "対象", "2025年 4月度"], 3: ["申請日", "2025-04-30", None, "精算日", "2025-05-10"], 5: ["日付", "行先", "目的", "交通機関", "出発地", "到着地", "片/往", "金額"]}, "widths": {"A": 12.0, "B": 16.0, "C": 18.0, "D": 14.0, "E": 12.0, "F": 12.0, "G": 8.0, "H": 12.0}},
    "fixed_asset_register": {"sheet_name": "固定資産台帳", "rows": {1: ["固定資産台帳"], 2: ["名称", "ノートPC", None, "番号", "FA-001"], 3: ["取得年月日", "2024-01-01", None, "所在", "東京"], 4: ["償却方法", "定額法", None, "償却率", 0.25], 6: ["日付", "摘要", "取得数量", "取得単価", "取得金額", "償却額", "異動数量", "異動金額", "現在数量", "現在金額", "事業専用割合", "必要経費算入額", "備考"]}, "widths": {"A": 12.0, "B": 22.0, "C": 10.0, "D": 12.0, "E": 12.0, "F": 12.0, "G": 10.0, "H": 12.0, "I": 10.0, "J": 12.0, "K": 12.0, "L": 12.0, "M": 16.0}},
    "fixed_asset_depreciation": {"sheet_name": "固定資産台帳 兼 減価償却計算表", "rows": {1: ["固定資産台帳 兼 減価償却計算表"], 4: ["勘定科目", "資産コード", "資産名", "取得日", "取得価額", "償却方法", "耐用年数", "償却率", "償却月数", "期首帳簿価額", "減価償却費", "本年末残高", "摘要"]}, "widths": {"A": 12.0, "B": 10.0, "C": 16.0, "D": 12.0, "E": 12.0, "F": 10.0, "G": 10.0, "H": 10.0, "I": 10.0, "J": 12.0, "K": 12.0, "L": 12.0, "M": 16.0}},
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
