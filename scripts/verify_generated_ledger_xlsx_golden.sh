#!/bin/sh
set -eu

ROOT="/Users/yutaro/project-profit-ios"

exec python3 "$ROOT/scripts/verify_generated_ledger_xlsx_golden.py"
