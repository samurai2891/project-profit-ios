#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path("/Users/yutaro/project-profit-ios")
INSPECTOR = ROOT / "scripts" / "inspect_xlsx_layout.py"
GENERATED = ROOT / ".golden-generated-xlsx"
LIBXLSXWRITER_WIDTH_PADDING = 0.7109375

EXPECTATIONS = {
    "profit_loss": {
        "path": GENERATED / "profit_loss.xlsx",
        "sheet_name": "損益計算書",
        "rows": {
            1: ["損益計算書", None, None],
            2: ["※ 単年度出力用。収入と費用を分けて表示。", None, None],
            3: ["年度", "2026年度", None],
            4: ["科目", "収入", "費用"],
            5: ["【収益の部】", None, None],
        },
        "widths": {"A": 34.0, "B": 16.0, "C": 16.0},
    },
    "balance_sheet": {
        "path": GENERATED / "balance_sheet.xlsx",
        "sheet_name": "貸借対照表",
        "rows": {
            1: ["貸借対照表", None, None, None, None],
            2: ["※ 単年度出力用。資産の部と負債・純資産の部を左右に分けて表示。", None, None, None, None],
            3: ["年度", "2026年度", None, None, None],
            4: ["資産の部", "金額", None, "負債・純資産の部", "金額"],
            5: ["資産の部", None, None, "負債の部", None],
        },
        "widths": {"A": 28.0, "B": 16.0, "C": 4.0, "D": 28.0, "E": 16.0},
    },
    "trial_balance": {
        "path": GENERATED / "trial_balance.xlsx",
        "sheet_name": "残高試算表",
        "rows": {
            1: ["残高試算表", None, None, None, None, None],
            4: ["帳簿名", "残高試算表", None, None, None, None],
            5: ["年度", "2026年度", None, None, None, None],
            9: ["コード", "勘定科目", "区分", "借方", "貸方", "残高"],
        },
        "widths": {"A": 10.0, "B": 20.0, "C": 10.0, "D": 12.0, "E": 12.0, "F": 12.0},
    },
    "journal": {
        "path": GENERATED / "journal.xlsx",
        "sheet_name": "仕訳帳",
        "rows": {
            1: ["仕訳帳", None, None, None, None, None, None],
            4: ["帳簿名", "仕訳帳", None, None, None, None, None],
            5: ["年度", "2026年度", None, None, None, None, None],
            9: ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"],
        },
        "widths": {"A": 7.0, "B": 7.0, "C": 18.0, "D": 14.0, "E": 18.0, "F": 14.0, "G": 28.0},
    },
    "ledger": {
        "path": GENERATED / "ledger.xlsx",
        "sheet_name": "総勘定元帳",
        "rows": {
            1: ["総勘定元帳（通常版）", None, None, None, None, None, None],
            4: ["帳簿名", "総勘定元帳", None, None, None, None, None],
            5: ["年度", "2026年度", None, None, None, None, None],
            10: ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"],
        },
        "widths": {"A": 8.0, "B": 8.0, "C": 18.0, "D": 26.0, "E": 14.0, "F": 14.0, "G": 16.0},
    },
    "fixed_assets": {
        "path": GENERATED / "fixed_assets.xlsx",
        "sheet_name": "固定資産台帳",
        "rows": {
            1: ["固定資産台帳 兼 減価償却計算表", None, None, None, None, None, None, None, None, None],
            4: ["帳簿名", "固定資産台帳 兼 減価償却計算表", None, None, None, None, None, None, None, None],
            5: ["年分", "2026年", None, None, None, None, None, None, None, None],
            9: ["勘定科目", "資産コード", "資産名", "資産の種類", "状態", "数量", "取得日", "取得価額", "償却方法", "耐用年数"],
        },
        "widths": {"A": 14.0, "B": 12.0, "C": 18.0, "D": 14.0, "E": 10.0, "F": 8.0, "G": 12.0, "H": 14.0, "I": 12.0, "J": 10.0},
    },
}


def inspect(path: Path) -> dict:
    result = subprocess.run(
        [sys.executable, str(INSPECTOR), str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"inspect failed: {path}")
    return json.loads(result.stdout)


def compare_cells(actual_row: list, expected_row: list, row_number: int, key: str) -> list[str]:
    errors = []
    for index, expected in enumerate(expected_row):
        actual = actual_row[index] if index < len(actual_row) else None
        if actual != expected:
            errors.append(
                f"{key}: row {row_number} col {index + 1} expected {expected!r} but got {actual!r}"
            )
    return errors


def verify(key: str) -> list[str]:
    spec = EXPECTATIONS[key]
    if not spec["path"].exists():
        return [f"{key}: missing generated workbook at {spec['path']}"]

    snapshot = inspect(spec["path"])
    errors = []
    if snapshot["sheet_name"] != spec["sheet_name"]:
        errors.append(
            f"{key}: expected sheet {spec['sheet_name']!r} but got {snapshot['sheet_name']!r}"
        )

    for row_number, expected_row in spec["rows"].items():
        actual_row = snapshot["rows"].get(str(row_number), [])
        errors.extend(compare_cells(actual_row, expected_row, row_number, key))

    for column, expected_width in spec["widths"].items():
        actual_width = snapshot["widths"].get(column)
        if actual_width is None:
            errors.append(f"{key}: missing width for column {column}")
        else:
            normalized_width = actual_width - LIBXLSXWRITER_WIDTH_PADDING
            if abs(normalized_width - expected_width) > 0.05:
                errors.append(
                    f"{key}: column {column} expected width {expected_width} but got {actual_width} (normalized {normalized_width})"
                )

    return errors


def main() -> int:
    all_errors = []
    for key in EXPECTATIONS:
        errors = verify(key)
        if errors:
            all_errors.extend(errors)
        else:
            print(f"PASS {key}")

    if all_errors:
        for error in all_errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
