#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

taxyear_json="$REPO_ROOT/ProjectProfit/Resources/TaxYear2025.json"
tax_year=""
form_key=""
ETAX_REFERENCE_ROOT_RESOLVED="$(resolve_etax_reference_root)"
default_schema_dir="$ETAX_REFERENCE_ROOT_RESOLVED/19XMLスキーマ/shotoku"
if [[ ! -d "$default_schema_dir" ]]; then
  default_schema_dir="$REPO_ROOT/tools/etax/xsd/shotoku"
fi
schema_dir="$default_schema_dir"

print_usage() {
  cat <<'EOF'
Usage:
  ./scripts/etax_resolve_xsd.sh --form-key <blue_general|blue_cash_basis|white_shushi> [options]

Options:
  --tax-year <year>       Tax year used for pack lookup (preferred)
  --taxyear-json <path>   Legacy TaxYear*.json path (fallback when pack form is missing)
  --schema-dir <path>     shotoku XSD directory (default: auto-detect ETAX_REFERENCE_ROOT -> tools/etax/xsd/shotoku)
  --form-key <name>       forms key in TaxYearPack filing (`blue_general`, `blue_cash_basis`, `white_shushi`)
EOF
}

print_result() {
  local status="$1"
  local reason="$2"
  local form_key_value="${3:-}"
  local form_id="${4:-}"
  local form_ver="${5:-}"
  local schema_path="${6:-}"
  local tax_year_value="${7:-}"
  local metadata_source="${8:-}"

  echo "status=$status"
  echo "reason=$reason"
  if [[ -n "$form_key_value" ]]; then
    echo "form_key=$form_key_value"
  fi
  if [[ -n "$form_id" ]]; then
    echo "form_id=$form_id"
  fi
  if [[ -n "$form_ver" ]]; then
    echo "form_ver=$form_ver"
  fi
  if [[ -n "$schema_path" ]]; then
    echo "schema_path=$schema_path"
  fi
  if [[ -n "$tax_year_value" ]]; then
    echo "tax_year=$tax_year_value"
  fi
  if [[ -n "$metadata_source" ]]; then
    echo "metadata_source=$metadata_source"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --taxyear-json)
      taxyear_json="$2"
      shift 2
      ;;
    --tax-year)
      tax_year="$2"
      shift 2
      ;;
    --schema-dir)
      schema_dir="$2"
      shift 2
      ;;
    --form-key)
      form_key="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print_result "error" "unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$form_key" ]]; then
  print_result "error" "--form-key is required"
  exit 1
fi

if [[ ! -d "$schema_dir" ]]; then
  print_result "error" "schema dir not found: $schema_dir" "$form_key"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  print_result "error" "python3 command is not available" "$form_key"
  exit 1
fi

set +e
parse_output="$(
python3 - "$REPO_ROOT" "$form_key" "$taxyear_json" "$tax_year" 2>&1 <<'PY'
import json
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
form_key = sys.argv[2]
taxyear_json_path = Path(sys.argv[3])
tax_year_raw = sys.argv[4].strip()

if tax_year_raw:
    if not tax_year_raw.isdigit():
        print(f"invalid --tax-year: {tax_year_raw}", file=sys.stderr)
        sys.exit(1)
    tax_year = int(tax_year_raw)
else:
    digits = "".join(ch for ch in taxyear_json_path.stem if ch.isdigit())
    tax_year = int(digits) if digits else 2025

pack_form_path = repo_root / "ProjectProfit" / "Resources" / "TaxYearPacks" / str(tax_year) / "filing" / f"{form_key}.json"
if pack_form_path.is_file():
    try:
        pack_form = json.loads(pack_form_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"failed to parse pack filing json: {pack_form_path} ({exc})", file=sys.stderr)
        sys.exit(1)

    form_id = str(pack_form.get("formId", "")).strip()
    form_ver = str(pack_form.get("formVer", "")).strip()
    if not form_id:
        print(f"pack formId is empty: {pack_form_path}", file=sys.stderr)
        sys.exit(1)
    if not form_ver:
        print(f"pack formVer is empty: {pack_form_path}", file=sys.stderr)
        sys.exit(1)

    print(f"{form_id}\t{form_ver}\tpack\t{tax_year}")
    sys.exit(0)

if not taxyear_json_path.is_file():
    print(
        f"pack form not found and legacy taxyear json not found: tax_year={tax_year}, "
        f"form_key={form_key}, path={taxyear_json_path}",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    data = json.loads(taxyear_json_path.read_text(encoding="utf-8"))
except Exception as exc:  # noqa: BLE001
    print(f"failed to parse legacy taxyear json: {taxyear_json_path} ({exc})", file=sys.stderr)
    sys.exit(1)

forms = data.get("forms")
if not isinstance(forms, dict):
    print(f"`forms` is missing in legacy taxyear json: {taxyear_json_path}", file=sys.stderr)
    sys.exit(1)

form = forms.get(form_key)
if not isinstance(form, dict):
    print(
        f"form key not found in pack and legacy taxyear json: "
        f"tax_year={tax_year}, form_key={form_key}",
        file=sys.stderr,
    )
    sys.exit(1)

form_id = str(form.get("formId", "")).strip()
form_ver = str(form.get("formVer", "")).strip()
if not form_id:
    print(f"ERROR: formId is empty: {form_key}", file=sys.stderr)
    sys.exit(1)
if not form_ver:
    print(f"ERROR: formVer is empty: {form_key}", file=sys.stderr)
    sys.exit(1)

print(f"{form_id}\t{form_ver}\tlegacy\t{tax_year}")
PY
)"
parse_exit=$?
set -e

if [[ "$parse_exit" -ne 0 ]]; then
  reason="$(awk 'NR == 1 { print; exit }' <<< "$parse_output")"
  if [[ -z "$reason" ]]; then
    reason="failed to parse form metadata"
  fi
  print_result "error" "$reason" "$form_key" "" "" "" "$tax_year"
  exit 1
fi

parse_result="$(awk 'END { print }' <<< "$parse_output")"
IFS=$'\t' read -r form_id form_ver metadata_source resolved_tax_year <<< "$parse_result"

if [[ -z "$form_id" || -z "$form_ver" || -z "$metadata_source" || -z "$resolved_tax_year" ]]; then
  print_result "error" "failed to parse resolved form metadata" "$form_key" "" "" "" "$tax_year"
  exit 1
fi

declare -a suffix_candidates=()
version_trimmed="$(printf '%s' "$form_ver" | tr -d '[:space:]')"
major_part="${version_trimmed%%.*}"
minor_part=""
if [[ "$version_trimmed" == *.* ]]; then
  minor_part="${version_trimmed#*.}"
fi
digits_only="$(printf '%s' "$version_trimmed" | tr -cd '0-9')"

if [[ "$major_part" =~ ^[0-9]+$ ]]; then
  suffix_candidates+=("$(printf '%03d' "$((10#$major_part))")")
fi
if [[ -n "$minor_part" && "$major_part" =~ ^[0-9]+$ && "$minor_part" =~ ^[0-9]+$ ]]; then
  suffix_candidates+=("$(printf '%03d' "$((10#$major_part * 10 + 10#$minor_part))")")
fi
if [[ "$digits_only" =~ ^[0-9]+$ ]]; then
  suffix_candidates+=("$(printf '%03d' "$((10#$digits_only))")")
fi

resolved_path=""
for suffix in "${suffix_candidates[@]-}"; do
  if [[ -z "$suffix" ]]; then
    continue
  fi
  candidate="$schema_dir/${form_id}-${suffix}.xsd"
  if [[ -f "$candidate" ]]; then
    resolved_path="$candidate"
    break
  fi
done

if [[ -n "$resolved_path" ]]; then
  print_result "ok" "resolved from formVer" "$form_key" "$form_id" "$form_ver" "$resolved_path" "$resolved_tax_year" "$metadata_source"
  exit 0
fi

shopt -s nullglob
matches=("$schema_dir/$form_id"-*.xsd)
shopt -u nullglob

if [[ "${#matches[@]}" -eq 0 ]]; then
  print_result "error" "no schema file found for formId: $form_id" "$form_key" "$form_id" "$form_ver" "" "$resolved_tax_year" "$metadata_source"
  exit 1
fi

latest_path=""
latest_suffix=-1
for path in "${matches[@]-}"; do
  if [[ -z "$path" ]]; then
    continue
  fi
  base="$(basename "$path")"
  suffix="${base#${form_id}-}"
  suffix="${suffix%.xsd}"
  if [[ "$suffix" =~ ^[0-9]+$ ]]; then
    value=$((10#$suffix))
    if (( value > latest_suffix )); then
      latest_suffix=$value
      latest_path="$path"
    fi
  fi
done

if [[ -z "$latest_path" ]]; then
  print_result "error" "schema suffix parse failed for formId: $form_id" "$form_key" "$form_id" "$form_ver" "" "$resolved_tax_year" "$metadata_source"
  exit 1
fi

print_result "warn" "formVer exact match not found, fallback to latest schema suffix" "$form_key" "$form_id" "$form_ver" "$latest_path" "$resolved_tax_year" "$metadata_source"
exit 0
