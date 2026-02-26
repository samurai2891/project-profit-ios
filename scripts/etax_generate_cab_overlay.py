#!/usr/bin/env python3
"""Generate CAB-derived requiredRule/idref/format overlay for TaxYear*.json.

This script reads e-taxall field-spec spreadsheets and maps metadata by xmlTag.
It intentionally limits sources to explicit KOA sheets to avoid mixing versions.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


NAMESPACE_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NAMESPACE_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
NAMESPACE_PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"


HEADER_ALIASES = {
    "input_type": {"入力型"},
    "format": {"書式"},
    "required_mark": {"入力ﾁｪｯｸ", "入力チェック", "入力ﾁｯｪｸ"},
    "xml_tag": {"xmlタグ", "ｘｍｌタグ"},
    "id_attr": {"id属性"},
    "idref_attr": {"idref属性"},
    "group_label": {"項目(ｸﾞﾙｰﾌﾟ)名", "項目（ｸﾞﾙｰﾌﾟ）名"},
    "item_label": {"項目名"},
}


DATA_TYPE_MAP = {
    "数値": "number",
    "文字": "text",
    "区分": "flag",
}


@dataclass(frozen=True)
class SpecRow:
    source_file: str
    source_sheet: str
    source_form: str
    source_row: int
    xml_tag: str
    input_type: str
    format_text: str
    required_mark: str
    id_attr: str
    idref_attr: str
    group_label: str
    item_label: str


def normalize_header(value: str | None) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    text = text.replace("　", "")
    text = re.sub(r"[\s_\-]+", "", text)
    return text.lower()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fp:
        return json.load(fp)


def col_to_index(cell_ref: str) -> int:
    col = 0
    for ch in cell_ref:
        if "A" <= ch <= "Z":
            col = col * 26 + (ord(ch) - ord("A") + 1)
        elif "a" <= ch <= "z":
            col = col * 26 + (ord(ch) - ord("a") + 1)
        else:
            break
    return col


def read_shared_strings(zip_file: zipfile.ZipFile) -> list[str]:
    shared_strings_path = "xl/sharedStrings.xml"
    if shared_strings_path not in zip_file.namelist():
        return []
    root = ET.fromstring(zip_file.read(shared_strings_path))
    items: list[str] = []
    for si in root.findall(f"{NAMESPACE_MAIN}si"):
        texts = [node.text or "" for node in si.findall(f".//{NAMESPACE_MAIN}t")]
        items.append("".join(texts))
    return items


def read_workbook_sheets(zip_file: zipfile.ZipFile) -> list[tuple[str, str]]:
    workbook_path = "xl/workbook.xml"
    rels_path = "xl/_rels/workbook.xml.rels"
    if workbook_path not in zip_file.namelist():
        raise ValueError("workbook.xml が見つかりません")
    if rels_path not in zip_file.namelist():
        raise ValueError("workbook.xml.rels が見つかりません")

    wb_root = ET.fromstring(zip_file.read(workbook_path))
    rels_root = ET.fromstring(zip_file.read(rels_path))

    rel_target_by_id: dict[str, str] = {}
    for rel in rels_root.findall(f"{NAMESPACE_PKG_REL}Relationship"):
        rel_id = rel.attrib.get("Id", "")
        target = rel.attrib.get("Target", "")
        if not rel_id or not target:
            continue
        normalized = target.lstrip("/")
        if not normalized.startswith("xl/"):
            normalized = f"xl/{normalized}"
        rel_target_by_id[rel_id] = normalized

    sheets: list[tuple[str, str]] = []
    for sheet in wb_root.findall(f".//{NAMESPACE_MAIN}sheet"):
        name = sheet.attrib.get("name", "").strip()
        rel_id = sheet.attrib.get(f"{NAMESPACE_REL}id", "").strip()
        target = rel_target_by_id.get(rel_id)
        if name and target:
            sheets.append((name, target))
    return sheets


def extract_cell_text(cell: ET.Element, shared_strings: list[str]) -> str:
    cell_type = cell.attrib.get("t", "")
    value_node = cell.find(f"{NAMESPACE_MAIN}v")
    if cell_type == "inlineStr":
        texts = [node.text or "" for node in cell.findall(f".//{NAMESPACE_MAIN}t")]
        return "".join(texts).strip()
    if value_node is None or value_node.text is None:
        return ""
    value_text = value_node.text.strip()
    if cell_type == "s":
        if not value_text:
            return ""
        try:
            idx = int(value_text)
        except ValueError:
            return ""
        if 0 <= idx < len(shared_strings):
            return shared_strings[idx].strip()
        return ""
    if cell_type == "b":
        if value_text == "1":
            return "TRUE"
        if value_text == "0":
            return "FALSE"
    return value_text


def canonical_data_type(input_type: str) -> str | None:
    text = input_type.strip()
    for token, mapped in DATA_TYPE_MAP.items():
        if token in text:
            return mapped
    return None


def normalize_required_rule(required_mark: str) -> str:
    text = required_mark.strip()
    if "○" in text:
        return "required"
    if not text:
        return "optional"
    return f"condition:{text}"


def normalize_format(format_text: str) -> str | None:
    text = format_text.strip()
    if not text:
        return None
    compact = text.replace(",", "")
    if re.fullmatch(r"9{7}", compact):
        return "digits7"
    if re.fullmatch(r"9{10}", compact):
        return "digits10"
    if re.fullmatch(r"9{11}", compact):
        return "digits11"
    return text


def resolve_form_key(field: dict[str, Any]) -> str:
    form = str(field.get("form") or "").strip()
    if form:
        return form
    key = str(field.get("internalKey") or "")
    if key.startswith("shushi_"):
        return "white_shushi"
    if key.startswith("declarant_"):
        return "common"
    return "blue_general"


def parse_spec_rows(
    xlsx_path: Path,
    sheet_name: str,
    source_form: str,
) -> list[SpecRow]:
    rows: list[SpecRow] = []
    with zipfile.ZipFile(xlsx_path, "r") as zip_file:
        shared_strings = read_shared_strings(zip_file)
        sheets = dict(read_workbook_sheets(zip_file))
        sheet_path = sheets.get(sheet_name)
        if sheet_path is None:
            raise ValueError(f"sheet が見つかりません: file={xlsx_path}, sheet={sheet_name}")
        if sheet_path not in zip_file.namelist():
            raise ValueError(f"sheet xml が見つかりません: {sheet_path}")

        root = ET.fromstring(zip_file.read(sheet_path))
        row_nodes = root.findall(f".//{NAMESPACE_MAIN}sheetData/{NAMESPACE_MAIN}row")
        if not row_nodes:
            return rows

        header_row_index = -1
        canonical_col: dict[str, int] = {}
        normalized_aliases = {
            key: {normalize_header(alias) for alias in aliases}
            for key, aliases in HEADER_ALIASES.items()
        }

        for row in row_nodes:
            row_num_text = row.attrib.get("r", "").strip()
            try:
                row_num = int(row_num_text) if row_num_text else 0
            except ValueError:
                row_num = 0

            by_col: dict[int, str] = {}
            for cell in row.findall(f"{NAMESPACE_MAIN}c"):
                ref = cell.attrib.get("r", "")
                col_index = col_to_index(ref) if ref else 0
                if col_index <= 0:
                    continue
                by_col[col_index] = extract_cell_text(cell, shared_strings).strip()

            if not by_col:
                continue

            if header_row_index < 0:
                detected: dict[str, int] = {}
                for col, text in by_col.items():
                    normalized = normalize_header(text)
                    for key, aliases in normalized_aliases.items():
                        if normalized in aliases and key not in detected:
                            detected[key] = col
                if "xml_tag" in detected and "input_type" in detected:
                    header_row_index = row_num
                    canonical_col = detected
                continue

            if row_num <= header_row_index:
                continue

            xml_tag_col = canonical_col.get("xml_tag")
            if xml_tag_col is None:
                continue
            xml_tag = by_col.get(xml_tag_col, "").strip()
            if not xml_tag:
                continue

            rows.append(
                SpecRow(
                    source_file=str(xlsx_path),
                    source_sheet=sheet_name,
                    source_form=source_form,
                    source_row=row_num,
                    xml_tag=xml_tag,
                    input_type=by_col.get(canonical_col.get("input_type", -1), "").strip(),
                    format_text=by_col.get(canonical_col.get("format", -1), "").strip(),
                    required_mark=by_col.get(canonical_col.get("required_mark", -1), "").strip(),
                    id_attr=by_col.get(canonical_col.get("id_attr", -1), "").strip(),
                    idref_attr=by_col.get(canonical_col.get("idref_attr", -1), "").strip(),
                    group_label=by_col.get(canonical_col.get("group_label", -1), "").strip(),
                    item_label=by_col.get(canonical_col.get("item_label", -1), "").strip(),
                )
            )

    if not rows:
        raise ValueError(f"対象行が0件です: file={xlsx_path}, sheet={sheet_name}")
    return rows


def aggregate_field_updates(
    field: dict[str, Any],
    rows: list[SpecRow],
    id_to_internal: dict[tuple[str, str], set[str]],
    unresolved_idrefs: list[dict[str, Any]],
    conflicts: dict[str, list[dict[str, Any]]],
) -> dict[str, Any]:
    updates: dict[str, Any] = {}
    internal_key = str(field.get("internalKey", ""))
    form_key = resolve_form_key(field)

    data_types = sorted({t for t in (canonical_data_type(row.input_type) for row in rows) if t})
    if len(data_types) == 1:
        updates["dataType"] = data_types[0]
    elif len(data_types) > 1:
        conflicts["dataType"].append(
            {"internalKey": internal_key, "values": data_types, "form": form_key}
        )

    formats = sorted({fmt for fmt in (normalize_format(row.format_text) for row in rows) if fmt})
    if len(formats) == 1:
        updates["format"] = formats[0]
    elif len(formats) > 1:
        conflicts["format"].append(
            {"internalKey": internal_key, "values": formats, "form": form_key}
        )

    required_rules = [normalize_required_rule(row.required_mark) for row in rows]
    if any(rule == "required" for rule in required_rules):
        updates["requiredRule"] = "required"
    elif any(rule.startswith("condition:") for rule in required_rules):
        updates["requiredRule"] = next(
            rule for rule in required_rules if rule.startswith("condition:")
        )
    else:
        updates["requiredRule"] = "optional"

    idref_candidates: set[str] = set()
    unresolved_raw: set[str] = set()
    for row in rows:
        raw = row.idref_attr.strip()
        if not raw:
            continue
        mapped = id_to_internal.get((form_key, raw), set())
        if len(mapped) == 1:
            idref_candidates.update(mapped)
        elif len(mapped) > 1:
            unresolved_raw.add(raw)
        elif raw == internal_key:
            idref_candidates.add(raw)
        else:
            unresolved_raw.add(raw)

    if len(idref_candidates) == 1:
        updates["idref"] = next(iter(idref_candidates))
    elif len(idref_candidates) > 1:
        conflicts["idref"].append(
            {
                "internalKey": internal_key,
                "values": sorted(idref_candidates),
                "form": form_key,
            }
        )

    if unresolved_raw:
        unresolved_idrefs.append(
            {
                "internalKey": internal_key,
                "form": form_key,
                "rawIdrefs": sorted(unresolved_raw),
            }
        )

    return updates


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate CAB overlay from e-taxall spec xlsx files.")
    parser.add_argument("--taxyear-json", required=True, help="TaxYear*.json path")
    parser.add_argument("--blue-spec-xlsx", required=True, help="KOA210 source xlsx")
    parser.add_argument("--blue-sheet", default="KOA210", help="KOA210 sheet name")
    parser.add_argument("--white-spec-xlsx", required=True, help="KOA110 source xlsx")
    parser.add_argument("--white-sheet", default="KOA110", help="KOA110 sheet name")
    parser.add_argument("--out-overlay", required=True, help="output overlay json path")
    parser.add_argument("--out-report", help="output report json path")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="未解決idrefや型競合がある場合に失敗する",
    )
    args = parser.parse_args()

    taxyear_path = Path(args.taxyear_json).resolve()
    blue_path = Path(args.blue_spec_xlsx).resolve()
    white_path = Path(args.white_spec_xlsx).resolve()
    out_overlay = Path(args.out_overlay).resolve()
    out_report = Path(args.out_report).resolve() if args.out_report else None

    for required_path in (taxyear_path, blue_path, white_path):
        if not required_path.exists():
            raise FileNotFoundError(f"file not found: {required_path}")

    taxyear = read_json(taxyear_path)
    fiscal_year = int(taxyear.get("fiscalYear", 0) or 0)
    fields = taxyear.get("fields")
    if not isinstance(fields, list) or not fields:
        raise ValueError("TaxYear json の fields が不正です")

    blue_rows = parse_spec_rows(blue_path, args.blue_sheet, source_form="blue_general")
    white_rows = parse_spec_rows(white_path, args.white_sheet, source_form="white_shushi")
    all_rows = blue_rows + white_rows

    rows_by_form_tag: dict[tuple[str, str], list[SpecRow]] = defaultdict(list)
    for row in all_rows:
        rows_by_form_tag[(row.source_form, row.xml_tag)].append(row)

    fields_by_form_tag: dict[tuple[str, str], list[str]] = defaultdict(list)
    for field in fields:
        if not isinstance(field, dict):
            continue
        internal_key = str(field.get("internalKey", "")).strip()
        xml_tag = str(field.get("xmlTag", "")).strip()
        if not internal_key or not xml_tag:
            continue
        form_key = resolve_form_key(field)
        if form_key == "common":
            fields_by_form_tag[("blue_general", xml_tag)].append(internal_key)
            fields_by_form_tag[("white_shushi", xml_tag)].append(internal_key)
        else:
            fields_by_form_tag[(form_key, xml_tag)].append(internal_key)

    # Build ID属性 -> internalKey index using rows that already map by xmlTag.
    id_to_internal: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in all_rows:
        id_attr = row.id_attr.strip()
        if not id_attr:
            continue
        mapped_keys = fields_by_form_tag.get((row.source_form, row.xml_tag), [])
        for key in mapped_keys:
            id_to_internal[(row.source_form, id_attr)].add(key)

    overlay_items: list[dict[str, Any]] = []
    missing_internal_keys: list[str] = []
    unresolved_idrefs: list[dict[str, Any]] = []
    conflicts: dict[str, list[dict[str, Any]]] = {"dataType": [], "format": [], "idref": []}

    for field in fields:
        if not isinstance(field, dict):
            continue
        internal_key = str(field.get("internalKey", "")).strip()
        xml_tag = str(field.get("xmlTag", "")).strip()
        if not internal_key or not xml_tag:
            continue

        form_key = resolve_form_key(field)
        selected_rows: list[SpecRow] = []
        if form_key == "common":
            selected_rows.extend(rows_by_form_tag.get(("blue_general", xml_tag), []))
            selected_rows.extend(rows_by_form_tag.get(("white_shushi", xml_tag), []))
        else:
            selected_rows.extend(rows_by_form_tag.get((form_key, xml_tag), []))

        if not selected_rows:
            missing_internal_keys.append(internal_key)
            continue

        updates = aggregate_field_updates(
            field=field,
            rows=selected_rows,
            id_to_internal=id_to_internal,
            unresolved_idrefs=unresolved_idrefs,
            conflicts=conflicts,
        )
        if not updates:
            continue
        overlay_items.append({"internalKey": internal_key, **updates})

    overlay_items.sort(key=lambda item: item["internalKey"])

    spec_xml_tags = {(row.source_form, row.xml_tag) for row in all_rows}
    taxyear_xml_tags = set(fields_by_form_tag.keys())
    unmapped_spec_keys = sorted(spec_xml_tags - taxyear_xml_tags)
    unmapped_spec_preview = [
        {"form": form, "xmlTag": xml_tag}
        for form, xml_tag in unmapped_spec_keys[:200]
    ]

    white_insurance_rows = [
        row
        for row in white_rows
        if "保険" in row.group_label or "保険" in row.item_label
    ]
    white_insurance_fact = [
        {
            "xmlTag": row.xml_tag,
            "groupLabel": row.group_label,
            "itemLabel": row.item_label,
            "sourceRow": row.source_row,
        }
        for row in white_insurance_rows
    ]

    payload = {
        "taxYear": fiscal_year,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": {
            "taxYearJson": str(taxyear_path),
            "blueSpecXlsx": str(blue_path),
            "blueSheet": args.blue_sheet,
            "whiteSpecXlsx": str(white_path),
            "whiteSheet": args.white_sheet,
        },
        "itemCount": len(overlay_items),
        "items": overlay_items,
    }

    out_overlay.parent.mkdir(parents=True, exist_ok=True)
    with out_overlay.open("w", encoding="utf-8") as fp:
        json.dump(payload, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    report = {
        "status": "ok",
        "taxYear": fiscal_year,
        "overlayItemCount": len(overlay_items),
        "taxYearFieldCount": len(fields),
        "missingFieldCount": len(missing_internal_keys),
        "missingInternalKeys": sorted(missing_internal_keys),
        "unresolvedIdrefCount": len(unresolved_idrefs),
        "unresolvedIdrefs": unresolved_idrefs,
        "conflictCount": {
            "dataType": len(conflicts["dataType"]),
            "format": len(conflicts["format"]),
            "idref": len(conflicts["idref"]),
        },
        "conflicts": conflicts,
        "unmappedSpecXmlTagCount": len(unmapped_spec_keys),
        "unmappedSpecXmlTagPreview": unmapped_spec_preview,
        "whiteInsuranceFacts": white_insurance_fact,
        "outputOverlay": str(out_overlay),
    }

    if out_report is not None:
        out_report.parent.mkdir(parents=True, exist_ok=True)
        with out_report.open("w", encoding="utf-8") as fp:
            json.dump(report, fp, ensure_ascii=False, indent=2)
            fp.write("\n")

    print(json.dumps(report, ensure_ascii=False))

    if args.strict:
        strict_errors = (
            len(unresolved_idrefs)
            + len(conflicts["dataType"])
            + len(conflicts["format"])
            + len(conflicts["idref"])
        )
        if strict_errors > 0:
            return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[etax_generate_cab_overlay] ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
