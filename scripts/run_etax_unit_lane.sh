#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "[1/4] Python unit tests (tag pipeline)"
python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'

echo "[2/4] Extract tags from fixtures"
python3 scripts/etax_extract_tags.py \
  --input-dir tools/etax/fixtures \
  --tax-year 2025 \
  --mapping-config tools/etax/mapping_rules_2025.json \
  --out-tag-dict /tmp/TagDictionary_2025.json \
  --base-taxyear-json tools/etax/fixtures/base_taxyear_2025.json \
  --out-taxyear-json /tmp/TaxYear2025.applied.json

echo "[3/4] Validate applied TaxYear"
python3 scripts/etax_validate_tags.py \
  --taxyear-json /tmp/TaxYear2025.applied.json \
  --required-keys tools/etax/required_internal_keys.json

echo "[4/4] Swift e-Tax unit tests (optional)"
set +e
health_output="$(bash scripts/check_simulator_health.sh 2>&1)"
health_exit=$?
set -e

echo "$health_output"

health_status="$(printf '%s\n' "$health_output" | awk -F= '/^status=/{print $2; exit}')"
health_reason="$(printf '%s\n' "$health_output" | awk -F= '/^reason=/{print $2; exit}')"
health_device="$(printf '%s\n' "$health_output" | awk -F= '/^simulator_device=/{print $2; exit}')"

if [[ "$health_exit" -eq 0 ]] && [[ "$health_status" == "ok" || "$health_status" == "warn" ]]; then
  simulator_device="${ETAX_SIMULATOR_DEVICE:-$health_device}"
  if [[ -z "$simulator_device" ]]; then
    simulator_device="iPhone 15"
  fi
  echo "swift lane device: $simulator_device"
  xcodebuild test \
    -project ProjectProfit.xcodeproj \
    -scheme ProjectProfit \
    -destination "platform=iOS Simulator,name=$simulator_device" \
    -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests \
    -only-testing:ProjectProfitTests/EtaxCharacterValidatorTests \
    -only-testing:ProjectProfitTests/EtaxXtxExporterTests \
    -only-testing:ProjectProfitTests/EtaxFieldPopulatorTests
else
  if [[ -z "$health_status" ]]; then
    health_status="error"
  fi
  if [[ -z "$health_reason" ]]; then
    health_reason="simulator health check failed"
  fi
  echo "skip: swift lane skipped (simulator-health status=$health_status reason=$health_reason)"
fi

echo "etax unit lane: success"
