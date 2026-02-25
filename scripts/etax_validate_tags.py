#!/usr/bin/env python3
"""Validate e-Tax tag mappings for coverage and consistency."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


VALID_DATA_TYPES = {"number", "text", "flag"}


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


def validate_entries(entries: list[dict[str, Any]], required_keys: set[str]) -> dict[str, Any]:
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
    parser.add_argument("--required-keys", required=True, help="required internal keys json")
    parser.add_argument("--out-report", help="validation report json")
    args = parser.parse_args()

    required_keys = flatten_required_keys(Path(args.required_keys).resolve())
    if not required_keys:
        raise ValueError("required keys が空です")

    if args.taxyear_json:
        entries = entries_from_taxyear(Path(args.taxyear_json).resolve())
        target = str(Path(args.taxyear_json).resolve())
    else:
        entries = entries_from_tag_dict(Path(args.tag_dict).resolve())
        target = str(Path(args.tag_dict).resolve())

    report = validate_entries(entries, required_keys)
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
