#!/usr/bin/env python3

import pathlib
import zipfile
import xml.etree.ElementTree as ET
from copy import deepcopy

from create_trial_balance_template import main as create_trial_balance_template_main


NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
NS_CT = "http://schemas.openxmlformats.org/package/2006/content-types"

ET.register_namespace("", NS_MAIN)
ET.register_namespace("r", NS_REL)

BASE = pathlib.Path(__file__).resolve().parent.parent / "ProjectProfit" / "Ledger" / "Resources" / "excel_templates"
SOURCE = BASE / "project-profit-ios_templates_consolidated_spreadsheet.xlsx"
OUTPUT_DIR = BASE / "ledgers"
REPORT_OUTPUT_DIR = BASE / "reports"

COMMON_SHEETS = [
    "Overview",
    "S00_Index_Index",
    "S01_Style_Guide",
    "S02_Accounts_Acct",
]

LEDGER_GROUPS = {
    "project-profit-ios_cash_book_template.xlsx": ["L01_CashStd_Form", "L01_CashStd_Sample", "L01_CashStd_Map", "L01_CashStd_Notes"],
    "project-profit-ios_cash_book_invoice_template.xlsx": ["L02_CashInv_Form", "L02_CashInv_Sample", "L02_CashInv_Map", "L02_CashInv_Notes"],
    "project-profit-ios_bank_account_book_template.xlsx": ["L03_BankStd_Form", "L03_BankStd_Sample", "L03_BankStd_Map", "L03_BankStd_Notes"],
    "project-profit-ios_bank_account_book_invoice_template.xlsx": ["L04_BankInv_Form", "L04_BankInv_Sample", "L04_BankInv_Map", "L04_BankInv_Notes"],
    "project-profit-ios_expense_book_template.xlsx": ["L05_ExpStd_Form", "L05_ExpStd_Sample", "L05_ExpStd_Map", "L05_ExpStd_Notes"],
    "project-profit-ios_expense_book_invoice_template.xlsx": ["L06_ExpInv_Form", "L06_ExpInv_Sample", "L06_ExpInv_Map", "L06_ExpInv_Notes"],
    "project-profit-ios_general_ledger_template.xlsx": ["L07_GLedStd_Form", "L07_GLedStd_Sample", "L07_GLedStd_Map", "L07_GLedStd_Notes"],
    "project-profit-ios_general_ledger_invoice_template.xlsx": ["L08_GLedInv_Form", "L08_GLedInv_Sample", "L08_GLedInv_Map", "L08_GLedInv_Notes"],
    "project-profit-ios_white_tax_bookkeeping_template.xlsx": ["L09_WhiteStd_Form", "L09_WhiteStd_Sample", "L09_WhiteStd_Map", "L09_WhiteStd_Notes"],
    "project-profit-ios_white_tax_bookkeeping_invoice_template.xlsx": ["L10_WhiteInv_Form", "L10_WhiteInv_Sample", "L10_WhiteInv_Map", "L10_WhiteInv_Notes"],
    "project-profit-ios_accounts_receivable_template.xlsx": ["L11_AR_Form", "L11_AR_Sample", "L11_AR_Map", "L11_AR_Notes"],
    "project-profit-ios_accounts_payable_template.xlsx": ["L12_AP_Form", "L12_AP_Sample", "L12_AP_Map", "L12_AP_Notes"],
    "project-profit-ios_journal_template.xlsx": ["L13_Journal_Form", "L13_Journal_Sample", "L13_Journal_Map", "L13_Journal_Notes"],
    "project-profit-ios_fixed_asset_register_template.xlsx": ["L14_FixReg_Form", "L14_FixReg_Sample", "L14_FixReg_Map", "L14_FixReg_Notes"],
    "project-profit-ios_fixed_asset_depreciation_template.xlsx": ["L15_FixDep_Form", "L15_FixDep_Sample", "L15_FixDep_Map", "L15_FixDep_Notes"],
    "project-profit-ios_transportation_expense_template.xlsx": ["L16_Travel_Form", "L16_Travel_Sample", "L16_Travel_Map", "L16_Travel_Notes"],
}

BSPL_SOURCE = BASE / "project-profit-ios_bs_pl_analysis_template.xlsx"
REPORT_GROUPS = {
    "project-profit-ios_balance_sheet_template.xlsx": [
        "BS_Form",
        "BS_Map",
        "TB_Detail",
        "COA_Master",
        "Journal_Input",
        "Overview",
        "SourceNotes",
    ],
    "project-profit-ios_profit_loss_template.xlsx": [
        "PL_Form",
        "PL_Map",
        "TB_Detail",
        "COA_Master",
        "Journal_Input",
        "Overview",
        "SourceNotes",
    ],
}


def split_workbook(source: pathlib.Path, output_dir: pathlib.Path, groups: dict[str, list[str]]) -> None:
    output_dir.mkdir(exist_ok=True)

    with zipfile.ZipFile(source, "r") as zin:
        workbook_root = ET.fromstring(zin.read("xl/workbook.xml"))
        rel_root = ET.fromstring(zin.read("xl/_rels/workbook.xml.rels"))
        content_types_root = ET.fromstring(zin.read("[Content_Types].xml"))

        sheets_parent = workbook_root.find(f"{{{NS_MAIN}}}sheets")
        sheet_info = [
            {
                "name": sheet.attrib["name"],
                "rid": sheet.attrib[f"{{{NS_REL}}}id"],
            }
            for sheet in list(sheets_parent)
        ]
        rel_info = {rel.attrib["Id"]: rel.attrib for rel in list(rel_root)}

    for file_name, keep_names in groups.items():
        keep_sheets = []
        for name in keep_names:
            matched = next((sheet for sheet in sheet_info if sheet["name"] == name), None)
            if matched is not None:
                keep_sheets.append(matched)
        keep_rids = {sheet["rid"] for sheet in keep_sheets}
        output_path = output_dir / file_name

        with zipfile.ZipFile(source, "r") as zin, zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zout:
            workbook_copy = deepcopy(workbook_root)
            workbook_sheets = workbook_copy.find(f"{{{NS_MAIN}}}sheets")
            for child in list(workbook_sheets):
                workbook_sheets.remove(child)
            for idx, sheet in enumerate(keep_sheets, start=1):
                element = ET.Element(f"{{{NS_MAIN}}}sheet")
                element.set("name", sheet["name"])
                element.set("sheetId", str(idx))
                element.set(f"{{{NS_REL}}}id", sheet["rid"])
                workbook_sheets.append(element)

            rel_copy = ET.Element(f"{{{NS_PKG}}}Relationships")
            for rel in list(rel_root):
                if "worksheet" in rel.attrib["Type"]:
                    if rel.attrib["Id"] in keep_rids:
                        rel_copy.append(deepcopy(rel))
                else:
                    rel_copy.append(deepcopy(rel))

            keep_targets = {
                rel_info[rid]["Target"] if rel_info[rid]["Target"].startswith("/") else f"/xl/{rel_info[rid]['Target']}"
                for rid in keep_rids
            }
            content_types_copy = deepcopy(content_types_root)
            for child in list(content_types_copy):
                if child.tag == f"{{{NS_CT}}}Override":
                    part_name = child.attrib.get("PartName")
                    if part_name and part_name.startswith("/xl/worksheets/") and part_name not in keep_targets:
                        content_types_copy.remove(child)

            for info in zin.infolist():
                if info.filename.startswith("xl/worksheets/"):
                    part_name = f"/{info.filename}"
                    if info.filename.startswith("xl/worksheets/_rels/"):
                        sheet_name = info.filename.removeprefix("xl/worksheets/_rels/").removesuffix(".rels")
                        part_name = f"/xl/worksheets/{sheet_name}"
                    if part_name not in keep_targets:
                        continue
                data = zin.read(info.filename)
                if info.filename == "xl/workbook.xml":
                    data = ET.tostring(workbook_copy, encoding="utf-8", xml_declaration=True)
                elif info.filename == "xl/_rels/workbook.xml.rels":
                    data = ET.tostring(rel_copy, encoding="utf-8", xml_declaration=True)
                elif info.filename == "[Content_Types].xml":
                    data = ET.tostring(content_types_copy, encoding="utf-8", xml_declaration=True)
                zout.writestr(info, data)


def main() -> None:
    ledger_groups = {
        file_name: module_sheets + COMMON_SHEETS
        for file_name, module_sheets in LEDGER_GROUPS.items()
    }
    split_workbook(SOURCE, OUTPUT_DIR, ledger_groups)
    create_trial_balance_template_main()
    split_workbook(BSPL_SOURCE, REPORT_OUTPUT_DIR, REPORT_GROUPS)

    print(f"Generated {len(LEDGER_GROUPS)} standalone ledger templates in {OUTPUT_DIR}")
    print("Generated 1 standalone trial balance template in ledgers/")
    print(f"Generated {len(REPORT_GROUPS)} standalone report templates in {REPORT_OUTPUT_DIR}")


if __name__ == "__main__":
    main()
