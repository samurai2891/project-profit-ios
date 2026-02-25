#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "[1/3] Python unit tests (tag pipeline)"
python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'

echo "[2/3] Extract tags from fixtures"
python3 scripts/etax_extract_tags.py \
  --input-dir tools/etax/fixtures \
  --tax-year 2025 \
  --mapping-config tools/etax/mapping_rules_2025.json \
  --out-tag-dict /tmp/TagDictionary_2025.json \
  --base-taxyear-json tools/etax/fixtures/base_taxyear_2025.json \
  --out-taxyear-json /tmp/TaxYear2025.applied.json

echo "[3/3] Validate applied TaxYear"
python3 scripts/etax_validate_tags.py \
  --taxyear-json /tmp/TaxYear2025.applied.json \
  --required-keys tools/etax/required_internal_keys.json

echo "etax unit lane: success"
