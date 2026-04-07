# Excel Templates

This directory stores the source-of-truth Excel originals referenced by the staged implementation materials.

Runtime ledger templates should use the standalone files under `ledgers/`.
The consolidated workbook is kept only as the upstream sample/source used to regenerate those standalone files.

- `project-profit-ios_bs_pl_analysis_template.xlsx`
  Official Balance Sheet / Profit & Loss template source only.
  Key sheets: `BS_Form`, `PL_Form`, `BS_Map`, `PL_Map`, `COA_Master`, `TB_Detail`, `SourceNotes`.

- `project-profit-ios_templates_consolidated_spreadsheet.xlsx`
  Consolidated ledger and form template source only.
  Includes `Form`, `Map`, `Sample`, and `Notes` sheets for books, inventory, BS, PL, and trial balance flows.

- `ledgers/*.xlsx`
  Standalone workbook per ledger.
  Each file keeps the shared guide sheets plus one `Lxx` module (`Form`, `Sample`, `Map`, `Notes`).
  `project-profit-ios_trial_balance_template.xlsx` is also stored here as the standalone source for the trial balance report layout.

- `reports/*.xlsx`
  Standalone workbook per report.
  `project-profit-ios_balance_sheet_template.xlsx` keeps the BS-focused sheets.
  `project-profit-ios_profit_loss_template.xlsx` keeps the PL-focused sheets.

The related Codex staged implementation prompt is stored at:

- `Docs/implementation/project-profit-ios_codex_staged_implementation_prompt.md`

Host-side golden verification for report templates is available via:

- `scripts/verify_report_xlsx_golden.py`
- `scripts/verify_report_xlsx_golden.sh`
- `scripts/verify_generated_report_xlsx_golden.py`
- `scripts/verify_generated_report_xlsx_golden.sh`
- `scripts/verify_ledger_xlsx_golden.py`
- `scripts/verify_ledger_xlsx_golden.sh`
- `scripts/verify_generated_ledger_xlsx_golden.py`
- `scripts/verify_generated_ledger_xlsx_golden.sh`

This compares workbook-level parity snapshots generated with `openpyxl`.
The current verification contract checks:

- workbook sheet order
- workbook defined names
- worksheet used range (`max_row`, `max_column`)
- full worksheet row payloads across the used range
- column widths
- merged cells
- freeze panes
- page setup / page margins / print area / print titles
- row breaks / column breaks
- non-empty cell snapshots:
  - value
  - formula
  - number format
  - font
  - fill
  - alignment
  - border

The current verification contract does not compare:

- row heights
- comments
- images / drawings / charts
- VBA / macros
- external links

`verify_generated_report_xlsx_golden.sh` first materializes fresh `.xlsx` output from `ExportCoordinator`
and then checks the generated workbooks against the same workbook-level contract.

`verify_generated_ledger_xlsx_golden.sh` does the same for ledger exports under `LedgerDataStore.exportExcel(...)`,
including invoice variants.

Committed expected snapshots live under:

- `scripts/golden_xlsx/templates/`
- `scripts/golden_xlsx/generated/`

They can be regenerated from the committed workbook fixtures with:

- `python3 scripts/generate_xlsx_golden_snapshots.py`
