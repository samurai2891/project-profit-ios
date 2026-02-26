#!/usr/bin/env python3
"""Extract e-Tax xmlTag definitions from source spreadsheets/csv files.

This script is designed to work even before CAB files are available:
- it supports CSV/TSV fixtures immediately
- it supports XLSX when `openpyxl` is installed
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import posixpath
import re
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET


VALID_DATA_TYPES = {"number", "text", "flag"}
DATA_TYPE_SYNONYMS = {
    "number": "number",
    "numeric": "number",
    "num": "number",
    "数値": "number",
    "金額": "number",
    "text": "text",
    "string": "text",
    "str": "text",
    "文字": "text",
    "文字列": "text",
    "flag": "flag",
    "bool": "flag",
    "boolean": "flag",
    "区分": "flag",
    "真偽": "flag",
}


@dataclass(frozen=True)
class SourceRow:
    source_file: str
    source_sheet: str
    source_row: int
    row: dict[str, str]


def normalize_header(value: str | None) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    text = re.sub(r"[\s_\-]+", "", text)
    return text.lower()


def normalize_label(value: str | None) -> str:
    if not value:
        return ""
    text = str(value).strip()
    text = text.replace("　", "")
    text = re.sub(r"\s+", "", text)
    return text


def normalize_token(value: str | None) -> str:
    if not value:
        return ""
    text = str(value).strip()
    return normalize_header(text)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fp:
        return json.load(fp)


def resolve_path(base_dir: Path, path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return (base_dir / path).resolve()


def load_required_keys(path: Path) -> set[str]:
    data = load_json(path)
    keys: set[str] = set()
    if isinstance(data, dict):
        for value in data.values():
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, str) and item:
                        keys.add(item)
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, str) and item:
                keys.add(item)
    return keys


def parse_csv_like(path: Path) -> list[SourceRow]:
    delimiter = "\t" if path.suffix.lower() == ".tsv" else ","
    rows: list[SourceRow] = []
    raw = path.read_bytes()
    decoded_text: str | None = None
    for encoding in ("utf-8-sig", "utf-8", "cp932", "shift_jis", "utf-16", "utf-16le", "utf-16be"):
        try:
            decoded_text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    if decoded_text is None:
        raise RuntimeError(f"CSV/TSV の文字コードを判定できません: {path}")

    fp = io.StringIO(decoded_text)
    reader = csv.DictReader(fp, delimiter=delimiter)
    if reader.fieldnames is None:
        return rows
    for row_index, raw_row in enumerate(reader, start=2):
        normalized_row: dict[str, str] = {}
        for key, value in raw_row.items():
            normalized_row[normalize_header(key)] = str(value).strip() if value is not None else ""
        rows.append(
            SourceRow(
                source_file=str(path),
                source_sheet="csv",
                source_row=row_index,
                row=normalized_row,
            )
        )
    return rows


def parse_xlsx(path: Path) -> list[SourceRow]:
    parser_preference = os.environ.get("ETAX_XLSX_PARSER", "").strip().lower()
    if parser_preference == "xml":
        return parse_xlsx_with_xml(path)
    try:
        import openpyxl  # type: ignore
    except ModuleNotFoundError:
        return parse_xlsx_with_xml(path)

    return parse_xlsx_with_openpyxl(path, openpyxl)


def parse_xlsx_with_openpyxl(path: Path, openpyxl: Any) -> list[SourceRow]:
    rows: list[SourceRow] = []
    workbook = openpyxl.load_workbook(path, data_only=True, read_only=True)
    for sheet in workbook.worksheets:
        values = sheet.iter_rows(values_only=True)
        try:
            headers = next(values)
        except StopIteration:
            continue
        header_keys = [normalize_header(str(h) if h is not None else "") for h in headers]
        for row_index, value_row in enumerate(values, start=2):
            if value_row is None:
                continue
            normalized_row: dict[str, str] = {}
            has_any_value = False
            for key, value in zip(header_keys, value_row):
                if not key:
                    continue
                text = str(value).strip() if value is not None else ""
                if text:
                    has_any_value = True
                normalized_row[key] = text
            if not has_any_value:
                continue
            rows.append(
                SourceRow(
                    source_file=str(path),
                    source_sheet=sheet.title,
                    source_row=row_index,
                    row=normalized_row,
                )
            )
    return rows


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
    ns_main = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    items: list[str] = []
    for si in root.findall(f"{ns_main}si"):
        texts = [node.text or "" for node in si.findall(f".//{ns_main}t")]
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

    ns_main = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    ns_rel = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
    ns_pkg_rel = "{http://schemas.openxmlformats.org/package/2006/relationships}"

    rel_target_by_id: dict[str, str] = {}
    for rel in rels_root.findall(f"{ns_pkg_rel}Relationship"):
        rel_id = rel.attrib.get("Id", "")
        target = rel.attrib.get("Target", "")
        if rel_id and target:
            normalized = target.lstrip("/")
            if not normalized.startswith("xl/"):
                normalized = posixpath.normpath(posixpath.join("xl", normalized))
            rel_target_by_id[rel_id] = normalized

    sheets: list[tuple[str, str]] = []
    for sheet in wb_root.findall(f".//{ns_main}sheet"):
        name = sheet.attrib.get("name", "").strip()
        rel_id = sheet.attrib.get(f"{ns_rel}id", "").strip()
        target = rel_target_by_id.get(rel_id)
        if name and target:
            sheets.append((name, target))
    return sheets


def extract_cell_text(cell: ET.Element, shared_strings: list[str], ns_main: str) -> str:
    cell_type = cell.attrib.get("t", "")
    value_node = cell.find(f"{ns_main}v")
    if cell_type == "inlineStr":
        texts = [node.text or "" for node in cell.findall(f".//{ns_main}t")]
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


def parse_sheet_rows(
    sheet_xml: bytes,
    sheet_name: str,
    source_file: str,
    shared_strings: list[str],
) -> list[SourceRow]:
    ns_main = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    root = ET.fromstring(sheet_xml)
    row_nodes = root.findall(f".//{ns_main}sheetData/{ns_main}row")
    if not row_nodes:
        return []

    row_data: list[tuple[int, dict[int, str]]] = []
    for row_pos, row in enumerate(row_nodes, start=1):
        row_num = row.attrib.get("r")
        try:
            row_index = int(row_num) if row_num else row_pos
        except ValueError:
            row_index = row_pos
        cells_by_col: dict[int, str] = {}
        sequential_col = 1
        for cell in row.findall(f"{ns_main}c"):
            cell_ref = cell.attrib.get("r", "")
            col_index = col_to_index(cell_ref) if cell_ref else sequential_col
            if col_index <= 0:
                col_index = sequential_col
            sequential_col = col_index + 1
            text = extract_cell_text(cell, shared_strings, ns_main)
            cells_by_col[col_index] = text
        row_data.append((row_index, cells_by_col))

    if not row_data:
        return []

    specialized = parse_xml_structure_rows(row_data, sheet_name=sheet_name, source_file=source_file)
    if specialized is not None:
        return specialized

    header_row_index, header_cells = row_data[0]
    if not header_cells:
        return []
    ordered_cols = sorted(header_cells.keys())
    header_keys = {
        col: normalize_header(header_cells.get(col, ""))
        for col in ordered_cols
    }
    if not any(header_keys.values()):
        return []

    parsed: list[SourceRow] = []
    for row_index, row_cells in row_data[1:]:
        normalized_row: dict[str, str] = {}
        has_any_value = False
        for col in ordered_cols:
            key = header_keys.get(col, "")
            if not key:
                continue
            value = row_cells.get(col, "").strip()
            if value:
                has_any_value = True
            normalized_row[key] = value
        if not has_any_value:
            continue
        parsed.append(
            SourceRow(
                source_file=source_file,
                source_sheet=sheet_name,
                source_row=row_index if row_index > header_row_index else (header_row_index + 1),
                row=normalized_row,
            )
        )
    return parsed


def parse_xml_structure_rows(
    row_data: list[tuple[int, dict[int, str]]],
    sheet_name: str,
    source_file: str,
) -> list[SourceRow] | None:
    header_row_index: int | None = None
    header_cells: dict[int, str] | None = None
    for row_index, cells in row_data[:30]:
        values = {idx: (text or "").strip() for idx, text in cells.items()}
        has_tag = any(value == "タグ名" for value in values.values())
        has_content = any("要素内容" in value for value in values.values())
        if has_tag and has_content:
            header_row_index = row_index
            header_cells = values
            break
    if header_row_index is None or header_cells is None:
        return None

    tag_col: int | None = None
    data_type_col: int | None = None
    content_col: int | None = None
    for col, value in header_cells.items():
        if value == "タグ名":
            tag_col = col
        if "共通ボキャブラリ" in value or value == "データ型":
            data_type_col = col
        if "要素内容" in value:
            content_col = col

    if tag_col is None or content_col is None:
        return None

    form_col: int | None = None
    for row_index, cells in row_data[:2]:
        if row_index != 1:
            continue
        for col, value in cells.items():
            text = (value or "").strip()
            if "様式" in text and ("ＩＤ" in text or "ID" in text):
                form_col = col
                break
        if form_col is not None:
            break

    form_value = sheet_name
    if form_col is not None:
        for row_index, cells in row_data:
            if row_index == 2:
                form_candidate = (cells.get(form_col, "") or "").strip()
                if form_candidate:
                    form_value = form_candidate
                break

    level_cols: list[int] = []
    for row_index, cells in row_data:
        if row_index <= header_row_index:
            continue
        numeric_cols = [
            col
            for col, value in cells.items()
            if re.fullmatch(r"\d+", (value or "").strip())
        ]
        if len(numeric_cols) >= 2:
            level_cols = sorted(numeric_cols)
            break

    if not level_cols:
        right_bound = min(
            value
            for value in [data_type_col, tag_col]
            if value is not None
        )
        level_cols = list(range(content_col, right_bound))
    if not level_cols:
        return None

    parsed: list[SourceRow] = []
    for row_index, cells in row_data:
        if row_index <= header_row_index + 1:
            continue
        tag = (cells.get(tag_col, "") or "").strip()
        if not tag:
            continue

        label = ""
        for col in sorted(level_cols, reverse=True):
            value = (cells.get(col, "") or "").strip()
            if value:
                label = value
                break
        if not label:
            continue

        data_type = ""
        if data_type_col is not None:
            data_type = (cells.get(data_type_col, "") or "").strip()

        parsed.append(
            SourceRow(
                source_file=source_file,
                source_sheet=sheet_name,
                source_row=row_index,
                row={
                    normalize_header("fieldLabelJP"): label,
                    normalize_header("xmlTag"): tag,
                    normalize_header("dataType"): data_type,
                    normalize_header("form"): form_value,
                },
            )
        )
    return parsed


def parse_xlsx_with_xml(path: Path) -> list[SourceRow]:
    rows: list[SourceRow] = []
    with zipfile.ZipFile(path, "r") as zip_file:
        shared_strings = read_shared_strings(zip_file)
        for sheet_name, sheet_path in read_workbook_sheets(zip_file):
            if sheet_path not in zip_file.namelist():
                continue
            sheet_rows = parse_sheet_rows(
                zip_file.read(sheet_path),
                sheet_name=sheet_name,
                source_file=str(path),
                shared_strings=shared_strings,
            )
            rows.extend(sheet_rows)
    return rows


def load_source_rows(input_dir: Path) -> list[SourceRow]:
    if not input_dir.exists():
        raise FileNotFoundError(f"入力ディレクトリが見つかりません: {input_dir}")
    rows: list[SourceRow] = []
    for path in sorted(input_dir.rglob("*")):
        if not path.is_file():
            continue
        suffix = path.suffix.lower()
        if suffix in {".csv", ".tsv"}:
            rows.extend(parse_csv_like(path))
        elif suffix == ".xlsx":
            rows.extend(parse_xlsx(path))
    return rows


def alias_key_map(column_aliases: dict[str, list[str]]) -> dict[str, list[str]]:
    return {
        field: [normalize_header(alias) for alias in aliases]
        for field, aliases in column_aliases.items()
    }


def first_value(row: dict[str, str], aliases: list[str]) -> str:
    for alias in aliases:
        value = row.get(alias, "").strip()
        if value:
            return value
    return ""


def canonical_data_type(value: str, fallback: str | None) -> str:
    token = normalize_token(value)
    if token in DATA_TYPE_SYNONYMS:
        return DATA_TYPE_SYNONYMS[token]
    if fallback:
        fb = normalize_token(fallback)
        if fb in DATA_TYPE_SYNONYMS:
            return DATA_TYPE_SYNONYMS[fb]
        if fallback in VALID_DATA_TYPES:
            return fallback
    return ""


def build_mapping_index(
    field_mappings: list[dict[str, Any]],
) -> tuple[
    dict[str, dict[str, Any]],
    dict[str, dict[str, Any]],
    dict[tuple[str, str, str], dict[str, Any]],
    dict[tuple[str, str], dict[str, Any]],
    dict[tuple[str, str], dict[str, Any]],
    dict[str, dict[str, Any]],
]:
    by_internal_key: dict[str, dict[str, Any]] = {}
    by_xml_tag: dict[str, dict[str, Any]] = {}
    by_label_section_form: dict[tuple[str, str, str], dict[str, Any]] = {}
    by_label_form: dict[tuple[str, str], dict[str, Any]] = {}
    by_label_section: dict[tuple[str, str], dict[str, Any]] = {}
    label_candidates: dict[str, list[dict[str, Any]]] = {}

    for mapping in field_mappings:
        internal_key = str(mapping.get("internal_key", "")).strip()
        if not internal_key:
            continue
        by_internal_key[internal_key] = mapping
        xml_tag = str(mapping.get("xml_tag", "")).strip()
        if xml_tag:
            by_xml_tag[xml_tag] = mapping
        label = normalize_label(str(mapping.get("field_label", "")))
        section = normalize_token(str(mapping.get("section", "")))
        form = normalize_token(str(mapping.get("form", "")))
        if label and section and form:
            by_label_section_form[(label, section, form)] = mapping
        if label and form:
            by_label_form[(label, form)] = mapping
        if label and section:
            by_label_section[(label, section)] = mapping
        if label:
            label_candidates.setdefault(label, []).append(mapping)
    by_label = {
        label: mappings[0]
        for label, mappings in label_candidates.items()
        if len(mappings) == 1
    }
    return by_internal_key, by_xml_tag, by_label_section_form, by_label_form, by_label_section, by_label


def resolve_mapping(
    row: dict[str, str],
    aliases: dict[str, list[str]],
    by_internal_key: dict[str, dict[str, Any]],
    by_xml_tag: dict[str, dict[str, Any]],
    by_label_section_form: dict[tuple[str, str, str], dict[str, Any]],
    by_label_form: dict[tuple[str, str], dict[str, Any]],
    by_label_section: dict[tuple[str, str], dict[str, Any]],
    by_label: dict[str, dict[str, Any]],
    form_aliases: dict[str, str],
) -> dict[str, Any] | None:
    row_internal_key = first_value(row, aliases.get("internal_key", []))
    if row_internal_key and row_internal_key in by_internal_key:
        return by_internal_key[row_internal_key]

    row_xml_tag = first_value(row, aliases.get("xml_tag", []))
    if row_xml_tag:
        mapped = by_xml_tag.get(row_xml_tag)
        if mapped is not None:
            return mapped
        # XML構造設計書は同一ラベルが大量にあるため、xmlTag不一致時のラベル推定は誤対応を招く。
        return None

    label = normalize_label(first_value(row, aliases.get("field_label", [])))
    section = normalize_token(first_value(row, aliases.get("section", [])))
    form = normalize_token(first_value(row, aliases.get("form", [])))
    if form in form_aliases:
        form = form_aliases[form]
    if label and section and form:
        mapped = by_label_section_form.get((label, section, form))
        if mapped is not None:
            return mapped
    if label and form:
        mapped = by_label_form.get((label, form))
        if mapped is not None:
            return mapped
    if label and section:
        mapped = by_label_section.get((label, section))
        if mapped is not None:
            return mapped
    if label and not form:
        return by_label.get(label)
    return None


def normalize_aliases_map(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    normalized: dict[str, str] = {}
    for k, v in value.items():
        if not isinstance(k, str) or not isinstance(v, str):
            continue
        source = normalize_token(k)
        target = normalize_token(v)
        if source and target:
            normalized[source] = target
    return normalized


def ensure_output_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def apply_tags_to_taxyear(base_taxyear: Path, out_taxyear: Path, items: list[dict[str, Any]]) -> None:
    base_data = load_json(base_taxyear)
    fields = base_data.get("fields")
    if not isinstance(fields, list):
        raise ValueError(f"`fields` が配列ではありません: {base_taxyear}")

    by_internal_key = {item["internalKey"]: item for item in items}
    missing_in_tags: list[str] = []

    for field in fields:
        if not isinstance(field, dict):
            continue
        internal_key = str(field.get("internalKey", "")).strip()
        if not internal_key:
            continue
        item = by_internal_key.get(internal_key)
        if item is None:
            missing_in_tags.append(internal_key)
            continue
        field["xmlTag"] = item["xmlTag"]
        field["dataType"] = item["dataType"]

    if missing_in_tags:
        raise ValueError(
            "TagDictionaryに存在しないinternalKeyがbase TaxYearにあります: "
            + ", ".join(sorted(set(missing_in_tags)))
        )

    ensure_output_parent(out_taxyear)
    with out_taxyear.open("w", encoding="utf-8") as fp:
        json.dump(base_data, fp, ensure_ascii=False, indent=2)
        fp.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract e-Tax tags from CAB/Excel/CSV sources.")
    parser.add_argument("--input-dir", required=True, help="展開済みCAB/Excel/CSVディレクトリ")
    parser.add_argument("--tax-year", required=True, type=int, help="対象年分")
    parser.add_argument("--mapping-config", required=True, help="mapping config json")
    parser.add_argument("--out-tag-dict", required=True, help="出力TagDictionary json")
    parser.add_argument("--base-taxyear-json", help="反映元TaxYear json")
    parser.add_argument("--out-taxyear-json", help="反映後TaxYear json")
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="required internal keys の一部欠落を許容する",
    )
    args = parser.parse_args()

    mapping_config_path = Path(args.mapping_config).resolve()
    mapping_config = load_json(mapping_config_path)
    config_dir = mapping_config_path.parent

    column_aliases = mapping_config.get("column_aliases", {})
    if not isinstance(column_aliases, dict):
        raise ValueError("mapping config の `column_aliases` が不正です")
    aliases = alias_key_map(column_aliases)

    field_mappings = mapping_config.get("field_mappings", [])
    if not isinstance(field_mappings, list) or not field_mappings:
        raise ValueError("mapping config の `field_mappings` が空または不正です")

    required_keys_file = mapping_config.get("required_keys_file")
    if not isinstance(required_keys_file, str) or not required_keys_file.strip():
        raise ValueError("mapping config に `required_keys_file` が必要です")
    required_keys_path = resolve_path(config_dir, required_keys_file)
    required_keys = load_required_keys(required_keys_path)

    (
        by_internal_key,
        by_xml_tag,
        by_label_section_form,
        by_label_form,
        by_label_section,
        by_label,
    ) = build_mapping_index(field_mappings)
    form_aliases = normalize_aliases_map(mapping_config.get("form_aliases", {}))

    source_rows = load_source_rows(Path(args.input_dir).resolve())
    if not source_rows:
        raise RuntimeError("入力ディレクトリに解析対象の行データがありません")

    extracted_items: list[dict[str, Any]] = []
    by_internal_extracted: dict[str, dict[str, Any]] = {}
    xml_tag_owner: dict[str, str] = {}
    skipped_rows = 0

    for source in source_rows:
        mapping = resolve_mapping(
            source.row,
            aliases,
            by_internal_key,
            by_xml_tag,
            by_label_section_form,
            by_label_form,
            by_label_section,
            by_label,
            form_aliases,
        )
        if mapping is None:
            skipped_rows += 1
            continue

        internal_key = str(mapping["internal_key"]).strip()
        xml_tag = first_value(source.row, aliases.get("xml_tag", [])) or str(mapping.get("xml_tag", "")).strip()
        if not xml_tag:
            raise ValueError(
                f"xmlTagが空です: internalKey={internal_key}, file={source.source_file}, row={source.source_row}"
            )

        row_data_type = first_value(source.row, aliases.get("data_type", []))
        data_type = canonical_data_type(row_data_type, str(mapping.get("data_type", "")).strip())
        if data_type not in VALID_DATA_TYPES:
            raise ValueError(
                "dataTypeが不正です: "
                f"internalKey={internal_key}, value={row_data_type or mapping.get('data_type')}"
            )

        existing = by_internal_extracted.get(internal_key)
        if existing is not None and existing["xmlTag"] != xml_tag:
            raise ValueError(
                "同一internalKeyに複数xmlTagが存在します: "
                f"{internal_key} -> {existing['xmlTag']} / {xml_tag}"
            )

        owner = xml_tag_owner.get(xml_tag)
        if owner is not None and owner != internal_key:
            raise ValueError(
                f"xmlTag重複: xmlTag={xml_tag}, internalKey={owner}, {internal_key}"
            )

        item = {
            "internalKey": internal_key,
            "xmlTag": xml_tag,
            "dataType": data_type,
            "requiredRule": mapping.get("required_rule"),
            "sourceFile": source.source_file,
            "sourceSheet": source.source_sheet,
            "sourceRow": source.source_row,
        }
        by_internal_extracted[internal_key] = item
        xml_tag_owner[xml_tag] = internal_key

    extracted_items = sorted(by_internal_extracted.values(), key=lambda x: x["internalKey"])
    missing_required = sorted(required_keys - set(by_internal_extracted.keys()))

    fallback_filled = 0
    for missing_key in missing_required:
        mapping = by_internal_key.get(missing_key)
        if mapping is None:
            continue
        xml_tag = str(mapping.get("xml_tag", "")).strip()
        data_type = canonical_data_type("", str(mapping.get("data_type", "")).strip())
        if not xml_tag or data_type not in VALID_DATA_TYPES:
            continue
        owner = xml_tag_owner.get(xml_tag)
        if owner is not None and owner != missing_key:
            continue
        item = {
            "internalKey": missing_key,
            "xmlTag": xml_tag,
            "dataType": data_type,
            "requiredRule": mapping.get("required_rule"),
            "sourceFile": str(mapping_config_path),
            "sourceSheet": "field_mappings:fallback",
            "sourceRow": 0,
        }
        by_internal_extracted[missing_key] = item
        xml_tag_owner[xml_tag] = missing_key
        fallback_filled += 1

    extracted_items = sorted(by_internal_extracted.values(), key=lambda x: x["internalKey"])
    missing_required = sorted(required_keys - set(by_internal_extracted.keys()))
    if missing_required and not args.allow_partial:
        raise ValueError(
            "required internalKey が不足しています: " + ", ".join(missing_required)
        )

    output = {
        "taxYear": args.tax_year,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceDirectory": str(Path(args.input_dir).resolve()),
        "itemCount": len(extracted_items),
        "skippedRowCount": skipped_rows,
        "fallbackFilledCount": fallback_filled,
        "missingRequiredKeys": missing_required,
        "items": extracted_items,
    }

    out_tag_dict = Path(args.out_tag_dict).resolve()
    ensure_output_parent(out_tag_dict)
    with out_tag_dict.open("w", encoding="utf-8") as fp:
        json.dump(output, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    if args.base_taxyear_json or args.out_taxyear_json:
        if not (args.base_taxyear_json and args.out_taxyear_json):
            raise ValueError("TaxYear反映には --base-taxyear-json と --out-taxyear-json の両方が必要です")
        apply_tags_to_taxyear(
            Path(args.base_taxyear_json).resolve(),
            Path(args.out_taxyear_json).resolve(),
            extracted_items,
        )

    print(
        json.dumps(
            {
                "status": "ok",
                "taxYear": args.tax_year,
                "itemCount": len(extracted_items),
                "skippedRowCount": skipped_rows,
                "fallbackFilledCount": fallback_filled,
                "missingRequiredKeyCount": len(missing_required),
                "output": str(out_tag_dict),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[etax_extract_tags] ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
