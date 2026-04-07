#!/usr/bin/env python3

from pathlib import Path

from xlsx_parity import compare_snapshots, inspect_workbook, load_snapshot


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "golden_xlsx" / "generated"
GENERATED = ROOT / ".golden-generated-xlsx"
WIDTH_PADDING = 0.7109375
REPORTS = {
    "profit_loss": GENERATED / "profit_loss.xlsx",
    "balance_sheet": GENERATED / "balance_sheet.xlsx",
    "trial_balance": GENERATED / "trial_balance.xlsx",
    "journal": GENERATED / "journal.xlsx",
    "ledger": GENERATED / "ledger.xlsx",
    "fixed_assets": GENERATED / "fixed_assets.xlsx",
}


def verify(key: str) -> list[str]:
    path = REPORTS[key]
    if not path.exists():
        return [f"{key}: missing generated workbook at {path}"]
    actual = inspect_workbook(path, width_padding=WIDTH_PADDING)
    expected = load_snapshot(FIXTURES / f"report__{key}.json")
    return compare_snapshots(key, actual, expected)


def main() -> int:
    errors: list[str] = []
    for key in REPORTS:
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
