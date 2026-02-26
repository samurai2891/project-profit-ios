#!/usr/bin/env python3
"""Apply CAB-derived overlay metadata to TaxYear*.json fields."""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


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

OVERLAY_FIELD_ALIASES = {
    "xmlTag": ("xmlTag", "xml_tag"),
    "dataType": ("dataType", "data_type", "type"),
    "idref": ("idref", "idRef"),
    "format": ("format",),
    "requiredRule": ("requiredRule", "required_rule"),
    "form": ("form", "formName", "form_name"),
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fp:
        return json.load(fp)


def normalize_string(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def normalize_data_type(value: Any) -> str | None:
    if value is None:
        return None
    text = normalize_string(value)
    if not text:
        return None
    lowered = text.lower()
    normalized = DATA_TYPE_SYNONYMS.get(lowered, lowered)
    if normalized not in VALID_DATA_TYPES:
        raise ValueError(f"dataType 不正: {value}")
    return normalized


def extract_internal_key(item: dict[str, Any]) -> str:
    for key in ("internalKey", "internal_key", "key"):
        if key in item:
            value = normalize_string(item.get(key))
            if value:
                return value
    raise ValueError("overlay item に internalKey がありません")


def normalize_overlay_updates(item: dict[str, Any]) -> dict[str, Any]:
    updates: dict[str, Any] = {}
    for canonical, aliases in OVERLAY_FIELD_ALIASES.items():
        alias_key: str | None = None
        for alias in aliases:
            if alias in item:
                alias_key = alias
                break
        if alias_key is None:
            continue
        raw_value = item.get(alias_key)
        if raw_value is None:
            updates[canonical] = None
            continue
        if canonical == "dataType":
            normalized = normalize_data_type(raw_value)
            if normalized is not None:
                updates[canonical] = normalized
            continue
        normalized_text = normalize_string(raw_value)
        if normalized_text:
            updates[canonical] = normalized_text
    return updates


def merge_updates(
    by_internal_key: dict[str, dict[str, Any]],
    internal_key: str,
    updates: dict[str, Any],
) -> None:
    existing = by_internal_key.get(internal_key)
    if existing is None:
        by_internal_key[internal_key] = updates
        return
    for key, value in updates.items():
        if key in existing and existing[key] != value:
            raise ValueError(
                f"同一internalKeyでoverlay値が競合: internalKey={internal_key}, key={key}, "
                f"{existing[key]} / {value}"
            )
        existing[key] = value


def overlay_entries(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        items = payload.get("items")
        if isinstance(items, list):
            return [item for item in items if isinstance(item, dict)]

        # key -> value map style
        mapped_entries: list[dict[str, Any]] = []
        for key, value in payload.items():
            if not isinstance(value, dict):
                continue
            entry = dict(value)
            entry.setdefault("internalKey", key)
            mapped_entries.append(entry)
        if mapped_entries:
            return mapped_entries

    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]

    raise ValueError("overlay json は `items` 配列 または key->value マップを指定してください")


def load_overlay(path: Path, strict: bool) -> tuple[dict[str, dict[str, Any]], int, int]:
    payload = load_json(path)
    entries = overlay_entries(payload)

    by_internal_key: dict[str, dict[str, Any]] = {}
    empty_update_count = 0
    for item in entries:
        internal_key = extract_internal_key(item)
        updates = normalize_overlay_updates(item)
        if not updates:
            empty_update_count += 1
            if strict:
                raise ValueError(f"overlay更新項目が空です: internalKey={internal_key}")
            continue
        merge_updates(by_internal_key, internal_key, updates)

    return by_internal_key, len(entries), empty_update_count


def validate_taxyear_integrity(fields: list[dict[str, Any]]) -> None:
    xml_tag_owner: dict[str, str] = {}
    for field in fields:
        internal_key = normalize_string(field.get("internalKey"))
        if not internal_key:
            continue

        data_type = field.get("dataType")
        if data_type is not None:
            normalized_type = normalize_data_type(data_type)
            if normalized_type is None:
                field["dataType"] = None
            else:
                field["dataType"] = normalized_type

        xml_tag = normalize_string(field.get("xmlTag"))
        if not xml_tag:
            continue
        owner = xml_tag_owner.get(xml_tag)
        if owner is not None and owner != internal_key:
            raise ValueError(
                f"xmlTag 重複: xmlTag={xml_tag}, internalKey={owner}, {internal_key}"
            )
        xml_tag_owner[xml_tag] = internal_key


def apply_overlay(
    base_taxyear: dict[str, Any],
    by_internal_key: dict[str, dict[str, Any]],
    strict: bool,
) -> dict[str, Any]:
    fields = base_taxyear.get("fields")
    if not isinstance(fields, list):
        raise ValueError("TaxYear json に `fields` がありません")

    by_field_key = {
        normalize_string(field.get("internalKey")): field
        for field in fields
        if isinstance(field, dict) and normalize_string(field.get("internalKey"))
    }
    taxyear_keys = set(by_field_key.keys())
    overlay_keys = set(by_internal_key.keys())
    unknown_overlay_keys = sorted(overlay_keys - taxyear_keys)
    if unknown_overlay_keys and strict:
        raise ValueError(
            "TaxYearに存在しないinternalKeyがoverlayに含まれます: "
            + ", ".join(unknown_overlay_keys)
        )

    touched_keys: set[str] = set()
    updated_counts: defaultdict[str, int] = defaultdict(int)
    for internal_key, updates in by_internal_key.items():
        field = by_field_key.get(internal_key)
        if field is None:
            continue
        for update_key, update_value in updates.items():
            field[update_key] = update_value
            updated_counts[update_key] += 1
        touched_keys.add(internal_key)

    validate_taxyear_integrity(fields)

    return {
        "touchedInternalKeyCount": len(touched_keys),
        "touchedInternalKeys": sorted(touched_keys),
        "unknownOverlayKeyCount": len(unknown_overlay_keys),
        "unknownOverlayKeys": unknown_overlay_keys,
        "updatedCounts": dict(sorted(updated_counts.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply CAB overlay values to TaxYear json.")
    parser.add_argument("--base-taxyear-json", required=True, help="入力TaxYear*.json")
    parser.add_argument("--overlay-json", required=True, help="overlay json")
    parser.add_argument("--out-taxyear-json", required=True, help="出力TaxYear*.json")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="未知internalKeyや空更新をエラーにする",
    )
    args = parser.parse_args()

    base_taxyear_path = Path(args.base_taxyear_json).resolve()
    overlay_path = Path(args.overlay_json).resolve()
    out_taxyear_path = Path(args.out_taxyear_json).resolve()

    base_taxyear = load_json(base_taxyear_path)
    by_internal_key, overlay_entry_count, empty_update_count = load_overlay(
        overlay_path, strict=args.strict
    )
    report = apply_overlay(base_taxyear, by_internal_key, strict=args.strict)

    out_taxyear_path.parent.mkdir(parents=True, exist_ok=True)
    with out_taxyear_path.open("w", encoding="utf-8") as fp:
        json.dump(base_taxyear, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    result = {
        "status": "ok",
        "appliedAt": datetime.now(timezone.utc).isoformat(),
        "strict": args.strict,
        "baseTaxYearJson": str(base_taxyear_path),
        "overlayJson": str(overlay_path),
        "outTaxYearJson": str(out_taxyear_path),
        "overlayEntryCount": overlay_entry_count,
        "emptyOverlayEntryCount": empty_update_count,
    }
    result.update(report)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[etax_apply_cab_overlay] ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
