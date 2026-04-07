#!/usr/bin/env python3

import argparse
from pathlib import Path

from xlsx_parity import compare_snapshots, inspect_workbook, load_snapshot


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "scripts" / "golden_xlsx" / "templates"
REPORTS = {
    "profit_loss": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/reports/project-profit-ios_profit_loss_template.xlsx",
    "balance_sheet": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/reports/project-profit-ios_balance_sheet_template.xlsx",
    "trial_balance": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_trial_balance_template.xlsx",
    "journal": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_journal_template.xlsx",
    "general_ledger": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_general_ledger_template.xlsx",
    "fixed_assets": ROOT / "ProjectProfit/Ledger/Resources/excel_templates/ledgers/project-profit-ios_fixed_asset_depreciation_template.xlsx",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify report xlsx templates against committed workbook snapshots."
    )
    parser.add_argument("targets", nargs="*", help="Subset of report templates to verify.")
    return parser.parse_args()


def verify(key: str) -> list[str]:
    actual = inspect_workbook(REPORTS[key])
    expected = load_snapshot(FIXTURES / f"report__{key}.json")
    return compare_snapshots(key, actual, expected)


def main() -> int:
    args = parse_args()
    targets = args.targets or list(REPORTS.keys())
    unknown = [target for target in targets if target not in REPORTS]
    if unknown:
        valid = ", ".join(sorted(REPORTS.keys()))
        for target in unknown:
            print(f"unknown target: {target} (valid: {valid})")
        return 2

    errors: list[str] = []
    for key in targets:
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
