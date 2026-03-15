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
  --taxyear-json <path>   TaxYear*.json path (default: ProjectProfit/Resources/TaxYear2025.json)
  --schema-dir <path>     shotoku XSD directory (default: auto-detect ETAX_REFERENCE_ROOT -> tools/etax/xsd/shotoku)
  --form-key <name>       forms key in TaxYear json
EOF
}

print_result() {
  local status="$1"
  local reason="$2"
  local form_key_value="${3:-}"
  local form_id="${4:-}"
  local form_ver="${5:-}"
  local schema_path="${6:-}"

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
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --taxyear-json)
      taxyear_json="$2"
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

if [[ ! -f "$taxyear_json" ]]; then
  print_result "error" "taxyear json not found: $taxyear_json" "$form_key"
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

parse_result="$(
python3 - "$taxyear_json" "$form_key" "$REPO_ROOT" <<'PY'
import json
import sys
from pathlib import Path

taxyear_json = Path(sys.argv[1])
form_key = sys.argv[2]
repo_root = Path(sys.argv[3])

data = json.loads(taxyear_json.read_text(encoding="utf-8"))
forms = data.get("forms")
if not isinstance(forms, dict):
    print("ERROR: `forms` is missing", file=sys.stderr)
    sys.exit(1)

form = forms.get(form_key)
if not isinstance(form, dict) and form_key == "blue_cash_basis":
    year = "".join(ch for ch in taxyear_json.stem if ch.isdigit())
    if year:
        pack_path = repo_root / "ProjectProfit" / "Resources" / "TaxYearPacks" / year / "filing" / "blue_cash_basis.json"
        if pack_path.is_file():
            pack = json.loads(pack_path.read_text(encoding="utf-8"))
            form = {
                "formId": pack.get("formId", ""),
                "formVer": pack.get("formVer", ""),
            }

if not isinstance(form, dict):
    print(f"ERROR: form key not found: {form_key}", file=sys.stderr)
    sys.exit(1)

form_id = str(form.get("formId", "")).strip()
form_ver = str(form.get("formVer", "")).strip()
if not form_id:
    print(f"ERROR: formId is empty: {form_key}", file=sys.stderr)
    sys.exit(1)
if not form_ver:
    print(f"ERROR: formVer is empty: {form_key}", file=sys.stderr)
    sys.exit(1)

print(f"{form_id}\t{form_ver}")
PY
)" || {
  reason="$(python3 - "$taxyear_json" "$form_key" "$REPO_ROOT" <<'PY'
import json
import sys
from pathlib import Path

taxyear_json = Path(sys.argv[1])
form_key = sys.argv[2]
repo_root = Path(sys.argv[3])

try:
    data = json.loads(taxyear_json.read_text(encoding="utf-8"))
except Exception as exc:  # noqa: BLE001
    print(f"failed to parse taxyear json: {exc}")
    raise SystemExit(0)

forms = data.get("forms")
if not isinstance(forms, dict):
    print("`forms` is missing")
    raise SystemExit(0)
if form_key not in forms:
    if form_key == "blue_cash_basis":
        year = "".join(ch for ch in taxyear_json.stem if ch.isdigit())
        if year:
            pack_path = repo_root / "ProjectProfit" / "Resources" / "TaxYearPacks" / year / "filing" / "blue_cash_basis.json"
            if pack_path.is_file():
                pack = json.loads(pack_path.read_text(encoding="utf-8"))
                form_id = str(pack.get("formId", "")).strip()
                form_ver = str(pack.get("formVer", "")).strip()
                if form_id and form_ver:
                    print("failed to parse form definition")
                    raise SystemExit(0)
    print(f"form key not found: {form_key}")
    raise SystemExit(0)
form = forms[form_key]
if not isinstance(form, dict):
    print(f"form definition is invalid: {form_key}")
    raise SystemExit(0)
form_id = str(form.get("formId", "")).strip()
form_ver = str(form.get("formVer", "")).strip()
if not form_id:
    print(f"formId is empty: {form_key}")
    raise SystemExit(0)
if not form_ver:
    print(f"formVer is empty: {form_key}")
    raise SystemExit(0)
print("failed to parse form definition")
PY
)"
  if [[ -z "$reason" ]]; then
    reason="failed to parse form definition"
  fi
  print_result "error" "$reason" "$form_key"
  exit 1
}

form_id="${parse_result%%$'\t'*}"
form_ver="${parse_result#*$'\t'}"

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
  print_result "ok" "resolved from formVer" "$form_key" "$form_id" "$form_ver" "$resolved_path"
  exit 0
fi

shopt -s nullglob
matches=("$schema_dir/$form_id"-*.xsd)
shopt -u nullglob

if [[ "${#matches[@]}" -eq 0 ]]; then
  print_result "error" "no schema file found for formId: $form_id" "$form_key" "$form_id" "$form_ver"
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
  print_result "error" "schema suffix parse failed for formId: $form_id" "$form_key" "$form_id" "$form_ver"
  exit 1
fi

print_result "warn" "formVer exact match not found, fallback to latest schema suffix" "$form_key" "$form_id" "$form_ver" "$latest_path"
exit 0
