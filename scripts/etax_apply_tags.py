#!/usr/bin/env python3
"""Apply TagDictionary xmlTag/dataType updates to TaxYear*.json."""

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


def load_tag_dict(path: Path) -> dict[str, dict[str, Any]]:
    raw = load_json(path)
    items = raw.get("items")
    if not isinstance(items, list):
        raise ValueError(f"`items` が見つかりません: {path}")
    by_internal_key: dict[str, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        internal_key = str(item.get("internalKey", "")).strip()
        xml_tag = str(item.get("xmlTag", "")).strip()
        data_type = str(item.get("dataType", "")).strip()
        if not internal_key:
            raise ValueError("TagDictionaryに internalKey 空が含まれます")
        if not xml_tag:
            raise ValueError(f"xmlTag が空です: internalKey={internal_key}")
        if data_type and data_type not in VALID_DATA_TYPES:
            raise ValueError(f"dataType 不正: internalKey={internal_key}, dataType={data_type}")
        existing = by_internal_key.get(internal_key)
        if existing is not None and existing["xmlTag"] != xml_tag:
            raise ValueError(
                f"同一internalKeyに複数xmlTag: {internal_key}, {existing['xmlTag']} / {xml_tag}"
            )
        by_internal_key[internal_key] = {
            "xmlTag": xml_tag,
            "dataType": data_type if data_type else existing.get("dataType") if existing else "",
        }
    return by_internal_key


def apply_tags(
    base_taxyear_json: Path,
    out_taxyear_json: Path,
    by_internal_key: dict[str, dict[str, Any]],
    allow_missing: bool,
) -> dict[str, Any]:
    base = load_json(base_taxyear_json)
    fields = base.get("fields")
    if not isinstance(fields, list):
        raise ValueError(f"`fields` が配列ではありません: {base_taxyear_json}")

    seen_internal_keys: set[str] = set()
    updated = 0
    missing: list[str] = []
    xml_tag_owner: dict[str, str] = {}

    for field in fields:
        if not isinstance(field, dict):
            continue
        internal_key = str(field.get("internalKey", "")).strip()
        if not internal_key:
            continue
        seen_internal_keys.add(internal_key)

        tag = by_internal_key.get(internal_key)
        if tag is None:
            missing.append(internal_key)
            continue

        field["xmlTag"] = tag["xmlTag"]
        if tag.get("dataType"):
            field["dataType"] = tag["dataType"]
        updated += 1

        owner = xml_tag_owner.get(tag["xmlTag"])
        if owner is not None and owner != internal_key:
            raise ValueError(
                f"xmlTag 重複: xmlTag={tag['xmlTag']}, internalKey={owner}, {internal_key}"
            )
        xml_tag_owner[tag["xmlTag"]] = internal_key

    unknown_tag_keys = sorted(set(by_internal_key.keys()) - seen_internal_keys)
    if missing and not allow_missing:
        raise ValueError(
            "TagDictionaryに存在しないinternalKeyがTaxYearにあります: " + ", ".join(sorted(set(missing)))
        )

    out_taxyear_json.parent.mkdir(parents=True, exist_ok=True)
    with out_taxyear_json.open("w", encoding="utf-8") as fp:
        json.dump(base, fp, ensure_ascii=False, indent=2)
        fp.write("\n")

    return {
        "updatedFieldCount": updated,
        "missingFieldCount": len(set(missing)),
        "missingFields": sorted(set(missing)),
        "unknownTagKeyCount": len(unknown_tag_keys),
        "unknownTagKeys": unknown_tag_keys,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply TagDictionary values to TaxYear json.")
    parser.add_argument("--base-taxyear-json", required=True, help="入力TaxYear*.json")
    parser.add_argument("--tag-dict", required=True, help="TagDictionary*.json")
    parser.add_argument("--out-taxyear-json", required=True, help="出力TaxYear*.json")
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="TaxYearにあるinternalKeyがTagDictionaryに未存在でも続行する",
    )
    args = parser.parse_args()

    base_taxyear = Path(args.base_taxyear_json).resolve()
    tag_dict = Path(args.tag_dict).resolve()
    out_taxyear = Path(args.out_taxyear_json).resolve()

    tag_map = load_tag_dict(tag_dict)
    result = apply_tags(base_taxyear, out_taxyear, tag_map, allow_missing=args.allow_missing)
    result.update(
        {
            "status": "ok",
            "appliedAt": datetime.now(timezone.utc).isoformat(),
            "baseTaxYearJson": str(base_taxyear),
            "tagDict": str(tag_dict),
            "outTaxYearJson": str(out_taxyear),
        }
    )
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[etax_apply_tags] ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
