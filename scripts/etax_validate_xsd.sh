#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

xml_path=""
schema_path=""
form_key=""
taxyear_json="$REPO_ROOT/ProjectProfit/Resources/TaxYear2025.json"
schema_dir="$REPO_ROOT/e-taxall/19XMLスキーマ/shotoku"

print_usage() {
  cat <<'EOF'
Usage:
  ./scripts/etax_validate_xsd.sh --xml <path> [--form-key <name> | --schema <path>] [options]

Options:
  --xml <path>            XML/XTX file path to validate
  --form-key <name>       forms key in TaxYear json (required when --schema is not used)
  --schema <path>         explicit XSD path (optional)
  --taxyear-json <path>   TaxYear*.json path
  --schema-dir <path>     shotoku XSD directory
EOF
}

print_result() {
  local status="$1"
  local reason="$2"
  local form_key_value="${3:-}"
  local schema_path_value="${4:-}"
  local xml_path_value="${5:-}"

  echo "status=$status"
  echo "reason=$reason"
  if [[ -n "$form_key_value" ]]; then
    echo "form_key=$form_key_value"
  fi
  if [[ -n "$schema_path_value" ]]; then
    echo "schema_path=$schema_path_value"
  fi
  if [[ -n "$xml_path_value" ]]; then
    echo "xml_path=$xml_path_value"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --xml)
      xml_path="$2"
      shift 2
      ;;
    --form-key)
      form_key="$2"
      shift 2
      ;;
    --schema)
      schema_path="$2"
      shift 2
      ;;
    --taxyear-json)
      taxyear_json="$2"
      shift 2
      ;;
    --schema-dir)
      schema_dir="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print_result "error" "unknown argument: $1" "$form_key" "$schema_path" "$xml_path"
      exit 1
      ;;
  esac
done

if [[ -z "$xml_path" ]]; then
  print_result "error" "--xml is required" "$form_key" "$schema_path"
  exit 1
fi

if [[ ! -f "$xml_path" ]]; then
  print_result "error" "xml file not found: $xml_path" "$form_key" "$schema_path" "$xml_path"
  exit 1
fi

if ! command -v xmllint >/dev/null 2>&1; then
  print_result "error" "xmllint command is not available" "$form_key" "$schema_path" "$xml_path"
  exit 1
fi

resolve_status="ok"
resolve_reason="explicit schema"
form_id=""
form_ver=""

if [[ -z "$schema_path" ]]; then
  if [[ -z "$form_key" ]]; then
    print_result "error" "--form-key is required when --schema is not provided" "" "" "$xml_path"
    exit 1
  fi

  set +e
  resolve_output="$(bash "$REPO_ROOT/scripts/etax_resolve_xsd.sh" \
    --taxyear-json "$taxyear_json" \
    --schema-dir "$schema_dir" \
    --form-key "$form_key" 2>&1)"
  resolve_exit=$?
  set -e

  printf '%s\n' "$resolve_output"

  resolve_status="$(printf '%s\n' "$resolve_output" | awk -F= '/^status=/{print $2; exit}')"
  resolve_reason="$(printf '%s\n' "$resolve_output" | awk -F= '/^reason=/{print $2; exit}')"
  form_id="$(printf '%s\n' "$resolve_output" | awk -F= '/^form_id=/{print $2; exit}')"
  form_ver="$(printf '%s\n' "$resolve_output" | awk -F= '/^form_ver=/{print $2; exit}')"
  schema_path="$(printf '%s\n' "$resolve_output" | awk -F= '/^schema_path=/{print $2; exit}')"

  if [[ "$resolve_exit" -ne 0 || -z "$schema_path" || "$resolve_status" == "error" ]]; then
    if [[ -z "$resolve_reason" ]]; then
      resolve_reason="failed to resolve schema path"
    fi
    print_result "error" "$resolve_reason" "$form_key" "$schema_path" "$xml_path"
    exit 1
  fi
fi

if [[ ! -f "$schema_path" ]]; then
  print_result "error" "schema file not found: $schema_path" "$form_key" "$schema_path" "$xml_path"
  exit 1
fi

validation_schema="$schema_path"
validation_xml="$xml_path"

# KOA/KOB系の単票XSDは root element が group 内定義のみのため、ラッパーXSD/XMLを生成して検証する。
if [[ -n "$form_id" && -n "$form_ver" ]]; then
  group_ver="$(printf '%s' "$form_ver" | tr -d '[:space:]' | tr '.' '-')"
  group_ver="$(printf '%s' "$group_ver" | tr -cd '0-9-')"
  group_name="${form_id}-${group_ver}group"

  if grep -q "name=\"$group_name\"" "$schema_path"; then
    wrapper_schema="$(mktemp -t etax-wrapper-schema)"
    wrapper_xml="$(mktemp -t etax-wrapper-xml)"
    schema_uri="$(python3 - "$schema_path" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve().as_uri())
PY
)"

    cat > "$wrapper_schema" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<xsd:schema
  targetNamespace="http://xml.e-tax.nta.go.jp/XSD/shotoku"
  xmlns="http://xml.e-tax.nta.go.jp/XSD/shotoku"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
  elementFormDefault="qualified"
  attributeFormDefault="unqualified">
  <xsd:include schemaLocation="$schema_uri"/>
  <xsd:element name="WRAP">
    <xsd:complexType>
      <xsd:sequence>
        <xsd:group ref="$group_name"/>
      </xsd:sequence>
    </xsd:complexType>
  </xsd:element>
</xsd:schema>
EOF

    root_fragment="$(xmllint --xpath '/*' "$xml_path" 2>/dev/null || true)"
    if [[ -z "$root_fragment" ]]; then
      print_result "error" "failed to extract xml root fragment" "$form_key" "$schema_path" "$xml_path"
      exit 1
    fi

    cat > "$wrapper_xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<WRAP xmlns="http://xml.e-tax.nta.go.jp/XSD/shotoku">
$root_fragment
</WRAP>
EOF

    validation_schema="$wrapper_schema"
    validation_xml="$wrapper_xml"
  fi
fi

set +e
xmllint_output="$(xmllint --noout --schema "$validation_schema" "$validation_xml" 2>&1)"
xmllint_exit=$?
set -e

printf '%s\n' "$xmllint_output"

if [[ "$xmllint_exit" -ne 0 ]]; then
  print_result "error" "xsd validation failed" "$form_key" "$schema_path" "$xml_path"
  exit 1
fi

if [[ "$resolve_status" == "warn" ]]; then
  print_result "warn" "xsd validation passed (schema resolution fallback)" "$form_key" "$schema_path" "$xml_path"
else
  print_result "ok" "xsd validation passed" "$form_key" "$schema_path" "$xml_path"
fi

exit 0
