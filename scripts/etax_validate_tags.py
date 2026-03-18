#!/usr/bin/env python3
"""Validate e-Tax tag mappings for coverage and consistency."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


VALID_DATA_TYPES = {"number", "text", "flag"}
REPEATED_XMLTAG_ALLOWED_PATTERNS = [
    re.compile(r"^shushi_(sales_detail|purchase_detail)_[1-4]_(name|address|invoice_registration|corporate_number|amount)$"),
    re.compile(r"^shushi_depreciation_detail_[1-6]_(name|acquired_year_month|acquisition_cost|method|useful_life|period_months|ordinary_amount|necessary_expense_amount|remaining_balance)$"),
    re.compile(r"^shushi_rent_detail_[1-2]_(address|name|property|key_money|renewal_fee|rent|necessary_expense)$"),
    re.compile(r"^bs_(asset|liability|equity)_additional_[1-7]_(name|closing)$"),
]


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fp:
        return json.load(fp)


def flatten_required_keys(path: Path) -> set[str]:
    raw = load_json(path)
    keys: set[str] = set()
    if isinstance(raw, dict):
        for value in raw.values():
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, str) and item:
                        keys.add(item)
    elif isinstance(raw, list):
        for item in raw:
            if isinstance(item, str) and item:
                keys.add(item)
    return keys


def entries_from_taxyear(path: Path) -> list[dict[str, Any]]:
    raw = load_json(path)
    fields = raw.get("fields")
    if not isinstance(fields, list):
        raise ValueError(f"`fields` が見つかりません: {path}")
    entries: list[dict[str, Any]] = []
    for field in fields:
        if not isinstance(field, dict):
            continue
        entries.append(
            {
                "internalKey": field.get("internalKey"),
                "xmlTag": field.get("xmlTag"),
                "dataType": field.get("dataType"),
                "source": str(path),
            }
        )
    return entries


def entries_from_tag_dict(path: Path) -> list[dict[str, Any]]:
    raw = load_json(path)
    items = raw.get("items")
    if not isinstance(items, list):
        raise ValueError(f"`items` が見つかりません: {path}")
    entries: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        entries.append(
            {
                "internalKey": item.get("internalKey"),
                "xmlTag": item.get("xmlTag"),
                "dataType": item.get("dataType"),
                "source": str(path),
            }
        )
    return entries


def entries_from_filing_dir(path: Path) -> list[dict[str, Any]]:
    filing_files = {
        "common": "common.json",
        "blue_general": "blue_general.json",
        "white_shushi": "white_shushi.json",
        "blue_cash_basis": "blue_cash_basis.json",
    }
    entries: list[dict[str, Any]] = []
    for form_key, file_name in filing_files.items():
        file_path = path / file_name
        if not file_path.exists():
            continue
        payload = load_json(file_path)
        sections = payload.get("sections")
        if not isinstance(sections, list):
            continue
        for section in sections:
            if not isinstance(section, dict):
                continue
            fields = section.get("fields")
            if not isinstance(fields, list):
                continue
            for field in fields:
                if not isinstance(field, dict):
                    continue
                entries.append(
                    {
                        "internalKey": field.get("internalKey"),
                        "fieldLabel": field.get("fieldLabel"),
                        "xmlTag": field.get("xmlTag"),
                        "dataType": field.get("dataType"),
                        "requiredRule": field.get("requiredRule"),
                        "formKey": form_key,
                        "source": str(file_path),
                    }
                )
    return entries


def allow_duplicate_xml_tag(internal_key: str) -> bool:
    return any(pattern.match(internal_key) for pattern in REPEATED_XMLTAG_ALLOWED_PATTERNS)


def expected_pack_keys_by_form() -> dict[str, set[str]]:
    common = {
        "declarant_name",
        "declarant_name_kana",
        "declarant_postal_code",
        "declarant_address",
        "declarant_phone",
        "declarant_business_name",
        "declarant_business_category",
    }
    blue_general = {
        "revenue_sales_revenue",
        "revenue_other_income",
        "expense_rent",
        "expense_utilities",
        "expense_travel",
        "expense_communication",
        "expense_advertising",
        "expense_entertainment",
        "expense_depreciation",
        "expense_insurance",
        "expense_interest",
        "expense_supplies",
        "expense_taxes",
        "expense_outsourcing",
        "expense_misc",
        "income_total_expenses",
        "income_net",
        "inventory_opening",
        "inventory_purchases",
        "inventory_closing",
        "bs_asset_cash",
        "bs_asset_checking_deposit",
        "bs_asset_time_deposit",
        "bs_asset_other_deposit",
        "bs_asset_notes_receivable",
        "bs_asset_accounts_receivable",
        "bs_asset_securities",
        "bs_asset_inventory",
        "bs_asset_prepayments",
        "bs_asset_loans_receivable",
        "bs_asset_buildings",
        "bs_asset_building_attachments",
        "bs_asset_machinery",
        "bs_asset_vehicles",
        "bs_asset_tools_fixtures_equipment",
        "bs_asset_land",
        "bs_asset_owner_draw",
        "bs_total_assets",
        "bs_liability_notes_payable",
        "bs_liability_accounts_payable",
        "bs_liability_loans_payable",
        "bs_liability_unpaid_amount",
        "bs_liability_advance_receipts",
        "bs_liability_deposits_received",
        "bs_liability_allowance_bad_debts",
        "bs_equity_owner_borrowings",
        "bs_equity_owner_capital",
        "bs_equity_income_before_blue_deduction",
        "bs_total_liabilities_and_equity",
    }
    for index in range(1, 8):
        blue_general |= {
            f"bs_asset_additional_{index}_name",
            f"bs_asset_additional_{index}_closing",
            f"bs_liability_additional_{index}_name",
            f"bs_liability_additional_{index}_closing",
            f"bs_equity_additional_{index}_name",
            f"bs_equity_additional_{index}_closing",
        }

    white_shushi = {
        "shushi_revenue_sales",
        "shushi_revenue_total",
        "shushi_revenue_home_consumption",
        "shushi_revenue_other",
        "shushi_inventory_opening",
        "shushi_inventory_purchases",
        "shushi_inventory_subtotal",
        "shushi_inventory_closing",
        "shushi_inventory_cogs",
        "shushi_income_gross",
        "shushi_expense_salary",
        "shushi_expense_outsourcing",
        "shushi_expense_depreciation",
        "shushi_expense_bad_debt",
        "shushi_expense_rent",
        "shushi_expense_interest",
        "shushi_expense_taxes",
        "shushi_expense_shipping",
        "shushi_expense_utilities",
        "shushi_expense_travel",
        "shushi_expense_communication",
        "shushi_expense_advertising",
        "shushi_expense_entertainment",
        "shushi_expense_insurance",
        "shushi_expense_repairs",
        "shushi_expense_supplies",
        "shushi_expense_welfare",
        "shushi_expense_additional_name",
        "shushi_expense_additional_amount",
        "shushi_expense_misc",
        "shushi_expense_other_subtotal",
        "shushi_expense_total",
        "shushi_income_before_employee_deduction",
        "shushi_employee_deduction",
        "shushi_income_net",
        "shushi_depreciation_next_total_label",
        "shushi_depreciation_total_ordinary",
        "shushi_depreciation_total_special",
        "shushi_depreciation_total_amount",
        "shushi_depreciation_total_necessary_expense",
        "shushi_depreciation_total_remaining_balance",
        "shushi_sales_detail_other_total",
        "shushi_sales_detail_reduced_tax_total",
        "shushi_sales_detail_total",
        "shushi_purchase_detail_other_total",
        "shushi_purchase_detail_reduced_tax_total",
        "shushi_purchase_detail_total",
        "shushi_rent_detail_1_address",
        "shushi_rent_detail_1_name",
        "shushi_rent_detail_1_property",
        "shushi_rent_detail_1_key_money",
        "shushi_rent_detail_1_renewal_fee",
        "shushi_rent_detail_1_rent",
        "shushi_rent_detail_1_necessary_expense",
        "shushi_rent_detail_2_address",
        "shushi_rent_detail_2_name",
        "shushi_rent_detail_2_property",
        "shushi_rent_detail_2_key_money",
        "shushi_rent_detail_2_renewal_fee",
        "shushi_rent_detail_2_rent",
        "shushi_rent_detail_2_necessary_expense",
    }
    for index in range(1, 5):
        white_shushi |= {
            f"shushi_sales_detail_{index}_name",
            f"shushi_sales_detail_{index}_address",
            f"shushi_sales_detail_{index}_invoice_registration",
            f"shushi_sales_detail_{index}_corporate_number",
            f"shushi_sales_detail_{index}_amount",
            f"shushi_purchase_detail_{index}_name",
            f"shushi_purchase_detail_{index}_address",
            f"shushi_purchase_detail_{index}_invoice_registration",
            f"shushi_purchase_detail_{index}_corporate_number",
            f"shushi_purchase_detail_{index}_amount",
        }
    for index in range(1, 7):
        white_shushi |= {
            f"shushi_depreciation_detail_{index}_name",
            f"shushi_depreciation_detail_{index}_acquired_year_month",
            f"shushi_depreciation_detail_{index}_acquisition_cost",
            f"shushi_depreciation_detail_{index}_method",
            f"shushi_depreciation_detail_{index}_useful_life",
            f"shushi_depreciation_detail_{index}_period_months",
            f"shushi_depreciation_detail_{index}_ordinary_amount",
            f"shushi_depreciation_detail_{index}_necessary_expense_amount",
            f"shushi_depreciation_detail_{index}_remaining_balance",
        }

    blue_cash_basis = {"cash_basis_revenue", "cash_basis_expense_total", "cash_basis_income"}
    return {
        "common": common,
        "blue_general": blue_general,
        "white_shushi": white_shushi,
        "blue_cash_basis": blue_cash_basis,
    }


def filing_dir_lint_errors(entries: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    grouped: dict[str, dict[str, dict[str, Any]]] = {}
    for entry in entries:
        form_key = str(entry.get("formKey", "")).strip()
        internal_key = str(entry.get("internalKey", "")).strip()
        if not form_key or not internal_key:
            continue
        grouped.setdefault(form_key, {})[internal_key] = entry

    required_forms = {"common", "blue_general", "white_shushi", "blue_cash_basis"}
    missing_forms = sorted(required_forms - set(grouped))
    if missing_forms:
        errors.append("required filing forms が不足: " + ", ".join(missing_forms))

    expected = expected_pack_keys_by_form()
    for form_key, expected_keys in expected.items():
        actual_keys = set(grouped.get(form_key, {}))
        missing_keys = sorted(expected_keys - actual_keys)
        if missing_keys:
            errors.append(f"pack coverage 不足 [{form_key}]: " + ", ".join(missing_keys))

    white_entries = grouped.get("white_shushi", {})
    required_rules = {
        "shushi_revenue_total",
        "shushi_inventory_subtotal",
        "shushi_inventory_cogs",
        "shushi_income_gross",
        "shushi_expense_other_subtotal",
        "shushi_expense_total",
        "shushi_income_before_employee_deduction",
        "shushi_income_net",
        "shushi_sales_detail_total",
        "shushi_purchase_detail_total",
        "shushi_depreciation_total_ordinary",
        "shushi_depreciation_total_special",
        "shushi_depreciation_total_amount",
        "shushi_depreciation_total_necessary_expense",
        "shushi_depreciation_total_remaining_balance",
    }
    missing_required_rules = sorted(
        key for key in required_rules
        if str(white_entries.get(key, {}).get("requiredRule", "")).strip() != "required"
    )
    if missing_required_rules:
        errors.append("white requiredRule 不足: " + ", ".join(missing_required_rules))

    if any(str(entry.get("xmlTag", "")).strip() == "AIG00020" for entry in white_entries.values()):
        errors.append("leaf-only mapping 違反: AIG00020 を direct field に割り当てています")
    invalid_ain = sorted(
        key for key, entry in white_entries.items()
        if str(entry.get("xmlTag", "")).strip() == "AIN00090"
        and ("合計" in str(entry.get("fieldLabel", "")) or str(entry.get("fieldLabel", "")) == "計")
    )
    if invalid_ain:
        errors.append("leaf-only mapping 違反: AIN00090 が total label に使われています: " + ", ".join(invalid_ain))

    page2_keys = {
        "shushi_sales_detail_total",
        "shushi_purchase_detail_total",
        "shushi_depreciation_total_necessary_expense",
        "shushi_rent_detail_1_necessary_expense",
    }
    missing_page2_keys = sorted(page2_keys - set(white_entries))
    if missing_page2_keys:
        errors.append("white page2 coverage 不足: " + ", ".join(missing_page2_keys))

    cash_keys = set(grouped.get("blue_cash_basis", {}))
    if "cash_basis_expense_total" not in cash_keys:
        errors.append("builder dynamic key coverage 不足: blue_cash_basis requires cash_basis_expense_total")

    return errors


def validate_entries(
    entries: list[dict[str, Any]],
    required_keys: set[str],
    *,
    strict_filing_pack: bool = False,
) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []

    seen_internal: set[str] = set()
    duplicated_internal: set[str] = set()
    xml_tag_owner: dict[str, str] = {}
    found_keys: set[str] = set()

    for entry in entries:
        internal_key = str(entry.get("internalKey", "")).strip()
        xml_tag = str(entry.get("xmlTag", "")).strip()
        data_type = str(entry.get("dataType", "")).strip()

        if not internal_key:
            errors.append("internalKey が空のエントリがあります")
            continue
        if internal_key in seen_internal:
            duplicated_internal.add(internal_key)
        seen_internal.add(internal_key)
        found_keys.add(internal_key)

        if not xml_tag:
            errors.append(f"xmlTag が空です: internalKey={internal_key}")
        else:
            owner = xml_tag_owner.get(xml_tag)
            if owner is not None and owner != internal_key:
                allow_duplicate = allow_duplicate_xml_tag(owner) and allow_duplicate_xml_tag(internal_key)
                if allow_duplicate:
                    continue
                errors.append(
                    f"xmlTag 重複: xmlTag={xml_tag}, internalKey={owner}, {internal_key}"
                )
            else:
                xml_tag_owner[xml_tag] = internal_key

        if data_type and data_type not in VALID_DATA_TYPES:
            errors.append(f"dataType 不正: internalKey={internal_key}, dataType={data_type}")
        if not data_type:
            warnings.append(f"dataType 未設定: internalKey={internal_key}")

    if duplicated_internal:
        errors.append(
            "internalKey 重複: " + ", ".join(sorted(duplicated_internal))
        )

    missing_required = sorted(required_keys - found_keys)
    if missing_required:
        errors.append(
            "required internalKey が不足: " + ", ".join(missing_required)
        )

    if strict_filing_pack:
        errors.extend(filing_dir_lint_errors(entries))

    return {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "entryCount": len(entries),
        "requiredKeyCount": len(required_keys),
        "missingRequiredCount": len(missing_required),
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate e-Tax tag mapping files.")
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--taxyear-json", help="TaxYear*.json")
    source_group.add_argument("--tag-dict", help="TagDictionary*.json")
    source_group.add_argument("--filing-dir", help="ProjectProfit/Resources/TaxYearPacks/<year>/filing")
    parser.add_argument("--required-keys", help="required internal keys json")
    parser.add_argument("--out-report", help="validation report json")
    args = parser.parse_args()

    if args.taxyear_json:
        if not args.required_keys:
            raise ValueError("--required-keys is required with --taxyear-json")
        required_keys = flatten_required_keys(Path(args.required_keys).resolve())
        if not required_keys:
            raise ValueError("required keys が空です")
        entries = entries_from_taxyear(Path(args.taxyear_json).resolve())
        target = str(Path(args.taxyear_json).resolve())
        strict_filing_pack = False
    elif args.tag_dict:
        if not args.required_keys:
            raise ValueError("--required-keys is required with --tag-dict")
        required_keys = flatten_required_keys(Path(args.required_keys).resolve())
        if not required_keys:
            raise ValueError("required keys が空です")
        entries = entries_from_tag_dict(Path(args.tag_dict).resolve())
        target = str(Path(args.tag_dict).resolve())
        strict_filing_pack = False
    else:
        required_keys = set()
        entries = entries_from_filing_dir(Path(args.filing_dir).resolve())
        target = str(Path(args.filing_dir).resolve())
        strict_filing_pack = True

    report = validate_entries(entries, required_keys, strict_filing_pack=strict_filing_pack)
    report["target"] = target

    if args.out_report:
        out_path = Path(args.out_report).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as fp:
            json.dump(report, fp, ensure_ascii=False, indent=2)
            fp.write("\n")

    print(json.dumps(report, ensure_ascii=False))
    if report["errors"]:
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[etax_validate_tags] ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
