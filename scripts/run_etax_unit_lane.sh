#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

resolve_etax_reference_root() {
  local candidates=()
  if [[ -n "${ETAX_REFERENCE_ROOT:-}" ]]; then
    candidates+=("${ETAX_REFERENCE_ROOT}")
  fi
  candidates+=(
    "$REPO_ROOT/e-taxall"
    "$REPO_ROOT/../project-profit-ios-local/e-taxall"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$REPO_ROOT/e-taxall"
}

ETAX_REFERENCE_ROOT_RESOLVED="$(resolve_etax_reference_root)"

artifact_dir="${ETAX_ARTIFACTS_DIR:-/tmp/etax-unit-lane}"
extract_input_dir="${ETAX_TAG_INPUT_DIR:-tools/etax/fixtures}"
overlay_json="${ETAX_CAB_OVERLAY_JSON:-tools/etax/fixtures/cab_overlay_2025.json}"
cab_blue_spec_xlsx="${ETAX_CAB_BLUE_FIELD_SPEC_XLSX:-$ETAX_REFERENCE_ROOT_RESOLVED/09XML構造設計書等【所得税】/帳票フィールド仕様書(所得-申告)Ver11x.xlsx}"
cab_blue_spec_sheet="${ETAX_CAB_BLUE_FIELD_SPEC_SHEET:-KOA210}"
cab_white_spec_xlsx="${ETAX_CAB_WHITE_FIELD_SPEC_XLSX:-$ETAX_REFERENCE_ROOT_RESOLVED/09XML構造設計書等【所得税】/帳票フィールド仕様書(所得-申告)Ver12x.xlsx}"
cab_white_spec_sheet="${ETAX_CAB_WHITE_FIELD_SPEC_SHEET:-KOA110}"
cab_spec_dir="${ETAX_CAB_SPEC_DIR:-$ETAX_REFERENCE_ROOT_RESOLVED/09XML構造設計書等【所得税】}"
xsd_require_generated_mode="${ETAX_XSD_REQUIRE_GENERATED_XML:-auto}"

tag_dict_json="$artifact_dir/TagDictionary_2025.json"
applied_taxyear_json="$artifact_dir/TaxYear2025.applied.json"
overlay_applied_taxyear_json="$artifact_dir/TaxYear2025.overlay.applied.json"
overlay_diff_json="$artifact_dir/TaxYear2025.overlay.diff.json"
overlay_diff_md="$artifact_dir/TaxYear2025.overlay.diff.md"
overlay_generated_json="$artifact_dir/cab_overlay_2025.generated.json"
overlay_generated_report_json="$artifact_dir/cab_overlay_2025.generated.report.json"

blue_export_xml="${ETAX_XSD_BLUE_EXPORT_XML:-$artifact_dir/KOA210.export.xml}"
white_export_xml="${ETAX_XSD_WHITE_EXPORT_XML:-$artifact_dir/KOA110.export.xml}"
xsd_blue_log="$artifact_dir/xsd_blue_validation.log"
xsd_white_log="$artifact_dir/xsd_white_validation.log"
xsd_summary_file="$artifact_dir/xsd_validation_summary.txt"

mkdir -p "$artifact_dir"

resolve_spec_path() {
  local preferred="$1"
  local search_dir="$2"
  local version_hint="$3"

  if [[ -f "$preferred" ]]; then
    printf '%s' "$preferred"
    return 0
  fi

  if [[ -d "$search_dir" ]]; then
    local candidate
    candidate="$(find "$search_dir" -maxdepth 1 -type f -name "*Ver${version_hint}.xlsx" | sort | head -n 1 || true)"
    if [[ -n "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  fi

  if [[ -d "$ETAX_REFERENCE_ROOT_RESOLVED" ]]; then
    local broad_candidate
    broad_candidate="$(
      find "$ETAX_REFERENCE_ROOT_RESOLVED" -type f -name "*Ver${version_hint}.xlsx" \
        | grep '所得-申告' \
        | grep '帳票' \
        | sort \
        | head -n 1 || true
    )"
    if [[ -n "$broad_candidate" ]]; then
      printf '%s' "$broad_candidate"
      return 0
    fi
  fi

  printf '%s' "$preferred"
}

cab_blue_spec_xlsx_resolved="$(resolve_spec_path "$cab_blue_spec_xlsx" "$cab_spec_dir" "11x")"
cab_white_spec_xlsx_resolved="$(resolve_spec_path "$cab_white_spec_xlsx" "$cab_spec_dir" "12x")"

echo "[1/8] Python unit tests (tag pipeline)"
python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'

echo "[2/8] Extract tags from source files"
python3 scripts/etax_extract_tags.py \
  --input-dir "$extract_input_dir" \
  --tax-year 2025 \
  --mapping-config tools/etax/mapping_rules_2025.json \
  --out-tag-dict "$tag_dict_json" \
  --base-taxyear-json tools/etax/fixtures/base_taxyear_2025.json \
  --out-taxyear-json "$applied_taxyear_json"

echo "[3/8] Validate applied TaxYear"
python3 scripts/etax_validate_tags.py \
  --taxyear-json "$applied_taxyear_json" \
  --required-keys tools/etax/required_internal_keys.json

overlay_to_apply="$overlay_json"

echo "[4/8] Generate CAB overlay from e-Tax reference specs (optional)"
if [[ -f "$cab_blue_spec_xlsx_resolved" ]] && [[ -f "$cab_white_spec_xlsx_resolved" ]]; then
  echo "info: resolved blue spec xlsx: $cab_blue_spec_xlsx_resolved"
  echo "info: resolved white spec xlsx: $cab_white_spec_xlsx_resolved"
  python3 scripts/etax_generate_cab_overlay.py \
    --taxyear-json ProjectProfit/Resources/TaxYear2025.json \
    --blue-spec-xlsx "$cab_blue_spec_xlsx_resolved" \
    --blue-sheet "$cab_blue_spec_sheet" \
    --white-spec-xlsx "$cab_white_spec_xlsx_resolved" \
    --white-sheet "$cab_white_spec_sheet" \
    --out-overlay "$overlay_generated_json" \
    --out-report "$overlay_generated_report_json"
  overlay_to_apply="$overlay_generated_json"
else
  echo "skip: cab overlay generation skipped (spec file not found: $cab_blue_spec_xlsx_resolved | $cab_white_spec_xlsx_resolved)"
fi

echo "[5/8] Apply CAB overlay (optional)"
if [[ -n "$overlay_to_apply" ]] && [[ -f "$overlay_to_apply" ]]; then
  python3 scripts/etax_apply_cab_overlay.py \
    --base-taxyear-json "$applied_taxyear_json" \
    --overlay-json "$overlay_to_apply" \
    --out-taxyear-json "$overlay_applied_taxyear_json"

  python3 scripts/etax_validate_tags.py \
    --taxyear-json "$overlay_applied_taxyear_json" \
    --required-keys tools/etax/required_internal_keys.json

  python3 scripts/etax_report_taxyear_diff.py \
    --before "$applied_taxyear_json" \
    --after "$overlay_applied_taxyear_json" \
    --out-json "$overlay_diff_json" \
    --out-md "$overlay_diff_md"
else
  echo "skip: cab overlay skipped (overlay file not found: $overlay_to_apply)"
fi

echo "[6/8] Swift e-Tax unit tests (optional)"
swift_lane_executed="false"
set +e
health_output="$(bash scripts/check_simulator_health.sh 2>&1)"
health_exit=$?
set -e

echo "$health_output"

health_status="$(printf '%s\n' "$health_output" | awk -F= '/^status=/{print $2; exit}')"
health_reason="$(printf '%s\n' "$health_output" | awk -F= '/^reason=/{print $2; exit}')"
health_device="$(printf '%s\n' "$health_output" | awk -F= '/^simulator_device=/{print $2; exit}')"

if [[ "$health_exit" -eq 0 ]] && [[ "$health_status" == "ok" || "$health_status" == "warn" ]]; then
  swift_lane_executed="true"
  simulator_device="${ETAX_SIMULATOR_DEVICE:-$health_device}"
  if [[ -z "$simulator_device" ]]; then
    simulator_device="iPhone 15"
  fi
  echo "swift lane device: $simulator_device"
  xcodebuild_log="$artifact_dir/xcodebuild_etax.log"
  ETAX_XSD_BLUE_EXPORT_XML="$blue_export_xml" \
  ETAX_XSD_WHITE_EXPORT_XML="$white_export_xml" \
  xcodebuild test \
    -project ProjectProfit.xcodeproj \
    -scheme ProjectProfit \
    -destination "platform=iOS Simulator,name=$simulator_device" \
    -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests \
    -only-testing:ProjectProfitTests/EtaxCharacterValidatorTests \
    -only-testing:ProjectProfitTests/EtaxXtxExporterTests \
    -only-testing:ProjectProfitTests/EtaxFieldPopulatorTests \
    -only-testing:ProjectProfitTests/ProfileSettingsViewTests 2>&1 | tee "$xcodebuild_log"

  python3 - "$xcodebuild_log" "$blue_export_xml" "$white_export_xml" <<'PY'
import base64
from pathlib import Path
import re
import sys

log_path = Path(sys.argv[1])
blue_out = Path(sys.argv[2])
white_out = Path(sys.argv[3])
log_text = log_path.read_text(encoding="utf-8", errors="ignore")

def extract(marker: str, output: Path) -> None:
    pattern = re.compile(
        rf"ETAX_EXPORT_{marker}_BASE64_BEGIN\s*(.*?)\s*ETAX_EXPORT_{marker}_BASE64_END",
        re.DOTALL,
    )
    match = pattern.search(log_text)
    if not match:
        print(f"info: no ETAX export marker found for {marker}")
        return

    payload = re.sub(r"\s+", "", match.group(1))
    if not payload:
        print(f"info: empty ETAX export payload for {marker}")
        return

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(base64.b64decode(payload))
    print(f"info: recovered ETAX export xml for {marker}: {output}")

extract("BLUE", blue_out)
extract("WHITE", white_out)
PY
else
  if [[ -z "$health_status" ]]; then
    health_status="error"
  fi
  if [[ -z "$health_reason" ]]; then
    health_reason="simulator health check failed"
  fi
  echo "skip: swift lane skipped (simulator-health status=$health_status reason=$health_reason)"
fi

echo "[7/8] XSD validation"
blue_sample_xml="${ETAX_XSD_BLUE_SAMPLE_XML:-$blue_export_xml}"
white_sample_xml="${ETAX_XSD_WHITE_SAMPLE_XML:-$white_export_xml}"
blue_fallback_xml="${ETAX_XSD_BLUE_FALLBACK_XML:-tools/etax/fixtures/KOA210_minimal.xml}"
white_fallback_xml="${ETAX_XSD_WHITE_FALLBACK_XML:-tools/etax/fixtures/KOA110_minimal.xml}"

require_generated_xml="false"
xsd_require_generated_mode_lc="$(printf '%s' "$xsd_require_generated_mode" | tr '[:upper:]' '[:lower:]')"
case "$xsd_require_generated_mode_lc" in
  true|1|yes)
    require_generated_xml="true"
    ;;
  false|0|no)
    require_generated_xml="false"
    ;;
  auto)
    if [[ "$swift_lane_executed" == "true" ]]; then
      require_generated_xml="true"
    fi
    ;;
  *)
    echo "error: ETAX_XSD_REQUIRE_GENERATED_XML must be one of auto|true|false (actual: $xsd_require_generated_mode)" >&2
    exit 1
    ;;
esac

echo "xsd require generated xml: $require_generated_xml (mode=$xsd_require_generated_mode)"

if [[ ! -f "$blue_sample_xml" ]]; then
  if [[ "$require_generated_xml" == "true" ]]; then
    echo "error: blue generated xml is required but missing: $blue_sample_xml" >&2
    exit 1
  fi
  blue_sample_xml="$blue_fallback_xml"
  echo "info: blue export xml not found, fallback to $blue_sample_xml"
fi
if [[ ! -f "$white_sample_xml" ]]; then
  if [[ "$require_generated_xml" == "true" ]]; then
    echo "error: white generated xml is required but missing: $white_sample_xml" >&2
    exit 1
  fi
  white_sample_xml="$white_fallback_xml"
  echo "info: white export xml not found, fallback to $white_sample_xml"
fi

if [[ ! -f "$blue_sample_xml" ]]; then
  echo "error: blue xsd validation input missing: $blue_sample_xml" >&2
  exit 1
fi
if [[ ! -f "$white_sample_xml" ]]; then
  echo "error: white xsd validation input missing: $white_sample_xml" >&2
  exit 1
fi

bash scripts/etax_validate_xsd.sh --xml "$blue_sample_xml" --form-key blue_general 2>&1 | tee "$xsd_blue_log"
bash scripts/etax_validate_xsd.sh --xml "$white_sample_xml" --form-key white_shushi 2>&1 | tee "$xsd_white_log"

cat > "$xsd_summary_file" <<EOF
blue_xml=$blue_sample_xml
white_xml=$white_sample_xml
require_generated_xml=$require_generated_xml
swift_lane_executed=$swift_lane_executed
EOF

echo "[8/8] Artifact summary"
echo "artifact_dir=$artifact_dir"
find "$artifact_dir" -maxdepth 1 -type f -print | sort

echo "etax unit lane: success"
