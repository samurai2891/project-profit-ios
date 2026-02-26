#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


TRACKED_PROPERTIES = (
    "xmlTag",
    "dataType",
    "requiredRule",
    "format",
    "idref",
    "taxLineRawValue",
    "fieldLabel",
    "form",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare two TaxYear JSON files and emit a machine-readable diff report."
    )
    parser.add_argument("--before", required=True, help="Base TaxYear JSON path")
    parser.add_argument("--after", required=True, help="Updated TaxYear JSON path")
    parser.add_argument("--out-json", required=True, help="Diff report JSON output path")
    parser.add_argument("--out-md", required=True, help="Diff report Markdown output path")
    return parser.parse_args()


def load_taxyear(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fp:
        payload = json.load(fp)
    if not isinstance(payload, dict):
        raise ValueError(f"TaxYear JSON must be an object: {path}")
    return payload


def build_field_map(payload: dict[str, Any], label: str) -> dict[str, dict[str, Any]]:
    fields = payload.get("fields")
    if not isinstance(fields, list):
        raise ValueError(f"`fields` must be a list in {label}")

    by_key: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(fields):
        if not isinstance(item, dict):
            raise ValueError(f"{label}: fields[{index}] must be object")
        internal_key = item.get("internalKey")
        if not isinstance(internal_key, str) or not internal_key.strip():
            raise ValueError(f"{label}: fields[{index}] has invalid internalKey")
        if internal_key in by_key:
            raise ValueError(f"{label}: duplicate internalKey: {internal_key}")
        by_key[internal_key] = item
    return by_key


def value_for_markdown(value: Any) -> str:
    if value is None:
        return "null"
    text = json.dumps(value, ensure_ascii=False)
    return text.replace("|", "\\|")


def generate_report(before_path: Path, after_path: Path) -> dict[str, Any]:
    before = load_taxyear(before_path)
    after = load_taxyear(after_path)
    before_fields = build_field_map(before, f"before({before_path})")
    after_fields = build_field_map(after, f"after({after_path})")

    before_keys = set(before_fields.keys())
    after_keys = set(after_fields.keys())

    added_keys = sorted(after_keys - before_keys)
    removed_keys = sorted(before_keys - after_keys)
    common_keys = sorted(before_keys & after_keys)

    changes: list[dict[str, Any]] = []
    for internal_key in common_keys:
        before_item = before_fields[internal_key]
        after_item = after_fields[internal_key]
        property_changes: list[dict[str, Any]] = []
        for prop in TRACKED_PROPERTIES:
            before_value = before_item.get(prop)
            after_value = after_item.get(prop)
            if before_value != after_value:
                property_changes.append(
                    {
                        "property": prop,
                        "before": before_value,
                        "after": after_value,
                    }
                )
        if property_changes:
            changes.append(
                {
                    "internalKey": internal_key,
                    "changes": property_changes,
                }
            )

    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "beforePath": str(before_path),
        "afterPath": str(after_path),
        "summary": {
            "beforeCount": len(before_fields),
            "afterCount": len(after_fields),
            "addedCount": len(added_keys),
            "removedCount": len(removed_keys),
            "changedFieldCount": len(changes),
        },
        "addedKeys": added_keys,
        "removedKeys": removed_keys,
        "changedFields": changes,
    }


def write_markdown(report: dict[str, Any], out_md: Path) -> None:
    summary = report["summary"]
    lines: list[str] = []
    lines.append("# TaxYear Diff Report")
    lines.append("")
    lines.append(f"- before: `{report['beforePath']}`")
    lines.append(f"- after: `{report['afterPath']}`")
    lines.append(f"- generatedAt: `{report['generatedAt']}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("| --- | ---: |")
    lines.append(f"| beforeCount | {summary['beforeCount']} |")
    lines.append(f"| afterCount | {summary['afterCount']} |")
    lines.append(f"| addedCount | {summary['addedCount']} |")
    lines.append(f"| removedCount | {summary['removedCount']} |")
    lines.append(f"| changedFieldCount | {summary['changedFieldCount']} |")
    lines.append("")

    added = report["addedKeys"]
    removed = report["removedKeys"]
    changed = report["changedFields"]

    lines.append("## Added Keys")
    lines.append("")
    if added:
        for key in added:
            lines.append(f"- `{key}`")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("## Removed Keys")
    lines.append("")
    if removed:
        for key in removed:
            lines.append(f"- `{key}`")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("## Property Changes")
    lines.append("")
    if changed:
        lines.append("| internalKey | property | before | after |")
        lines.append("| --- | --- | --- | --- |")
        for item in changed:
            internal_key = item["internalKey"]
            for prop_change in item["changes"]:
                prop = prop_change["property"]
                before_value = value_for_markdown(prop_change["before"])
                after_value = value_for_markdown(prop_change["after"])
                lines.append(
                    f"| `{internal_key}` | `{prop}` | `{before_value}` | `{after_value}` |"
                )
    else:
        lines.append("変更なし")
    lines.append("")

    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    before_path = Path(args.before).resolve()
    after_path = Path(args.after).resolve()
    out_json = Path(args.out_json).resolve()
    out_md = Path(args.out_md).resolve()

    report = generate_report(before_path=before_path, after_path=after_path)

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_markdown(report, out_md=out_md)

    print(
        "diff report generated:",
        f"changedFieldCount={report['summary']['changedFieldCount']}",
        f"addedCount={report['summary']['addedCount']}",
        f"removedCount={report['summary']['removedCount']}",
    )
    print(f"out_json={out_json}")
    print(f"out_md={out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
