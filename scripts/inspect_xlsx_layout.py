#!/usr/bin/env python3

import argparse
import json
from pathlib import Path

from xlsx_parity import inspect_workbook


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a workbook-level xlsx parity snapshot as JSON."
    )
    parser.add_argument("xlsx_path", help="Workbook path to inspect.")
    parser.add_argument(
        "--width-padding",
        type=float,
        default=0.0,
        help="Subtract this value from column widths before serializing.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = inspect_workbook(Path(args.xlsx_path), width_padding=args.width_padding)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
