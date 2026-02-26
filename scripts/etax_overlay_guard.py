#!/usr/bin/env python3
"""Guard CAB overlay report metrics for CI monitoring."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fp:
        raw = json.load(fp)
    if not isinstance(raw, dict):
        raise ValueError("report json must be an object")
    return raw


def count_list(value: Any) -> int:
    if isinstance(value, list):
        return len(value)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Guard CAB overlay report metrics.")
    parser.add_argument("--report", required=True, help="cab_overlay_2025.generated.report.json")
    parser.add_argument(
        "--max-missing-internal-keys",
        type=int,
        default=0,
        help="maximum allowed missingInternalKeys count",
    )
    parser.add_argument(
        "--max-unresolved-idrefs",
        type=int,
        default=0,
        help="maximum allowed unresolvedIdrefs count",
    )
    parser.add_argument("--out-json", help="optional guard summary json")
    parser.add_argument("--out-text", help="optional guard summary text")
    args = parser.parse_args()

    report_path = Path(args.report).resolve()
    if not report_path.is_file():
        summary = {
            "status": "error",
            "reason": f"overlay report not found: {report_path}",
            "reportPath": str(report_path),
            "missingInternalKeysCount": 0,
            "unresolvedIdrefsCount": 0,
            "maxMissingInternalKeys": args.max_missing_internal_keys,
            "maxUnresolvedIdrefs": args.max_unresolved_idrefs,
        }
        emit(summary, args.out_json, args.out_text)
        return 1

    report = load_json(report_path)

    missing_internal_keys = report.get("missingInternalKeys")
    unresolved_idrefs = report.get("unresolvedIdrefs")

    missing_count = count_list(missing_internal_keys)
    unresolved_count = count_list(unresolved_idrefs)

    errors: list[str] = []
    if missing_count > args.max_missing_internal_keys:
        errors.append(
            "missingInternalKeys threshold exceeded "
            f"(actual={missing_count} max={args.max_missing_internal_keys})"
        )
    if unresolved_count > args.max_unresolved_idrefs:
        errors.append(
            "unresolvedIdrefs threshold exceeded "
            f"(actual={unresolved_count} max={args.max_unresolved_idrefs})"
        )

    summary = {
        "status": "ok" if not errors else "error",
        "reason": "overlay guard passed" if not errors else "; ".join(errors),
        "reportPath": str(report_path),
        "missingInternalKeysCount": missing_count,
        "unresolvedIdrefsCount": unresolved_count,
        "maxMissingInternalKeys": args.max_missing_internal_keys,
        "maxUnresolvedIdrefs": args.max_unresolved_idrefs,
    }
    emit(summary, args.out_json, args.out_text)
    return 0 if not errors else 1


def emit(summary: dict[str, Any], out_json: str | None, out_text: str | None) -> None:
    print(f"status={summary['status']}")
    print(f"reason={summary['reason']}")
    print(f"report_path={summary['reportPath']}")
    print(f"missingInternalKeysCount={summary['missingInternalKeysCount']}")
    print(f"unresolvedIdrefsCount={summary['unresolvedIdrefsCount']}")
    print(f"maxMissingInternalKeys={summary['maxMissingInternalKeys']}")
    print(f"maxUnresolvedIdrefs={summary['maxUnresolvedIdrefs']}")

    if out_json:
        out_json_path = Path(out_json).resolve()
        out_json_path.parent.mkdir(parents=True, exist_ok=True)
        with out_json_path.open("w", encoding="utf-8") as fp:
            json.dump(summary, fp, ensure_ascii=False, indent=2)
            fp.write("\n")

    if out_text:
        out_text_path = Path(out_text).resolve()
        out_text_path.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            f"status={summary['status']}",
            f"reason={summary['reason']}",
            f"report_path={summary['reportPath']}",
            f"missingInternalKeysCount={summary['missingInternalKeysCount']}",
            f"unresolvedIdrefsCount={summary['unresolvedIdrefsCount']}",
            f"maxMissingInternalKeys={summary['maxMissingInternalKeys']}",
            f"maxUnresolvedIdrefs={summary['maxUnresolvedIdrefs']}",
        ]
        out_text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
