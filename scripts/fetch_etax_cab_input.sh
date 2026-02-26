#!/usr/bin/env bash
set -euo pipefail

# Fetch CAB input archive and expose extracted directory for ETAX_TAG_INPUT_DIR.
#
# Environment variables:
#   ETAX_CAB_SOURCE_URL            required when ETAX_CAB_SOURCE_REQUIRED=true
#   ETAX_CAB_SOURCE_REQUIRED       true|false (default: false)
#   ETAX_CAB_SOURCE_SHA256         optional expected sha256
#   ETAX_CAB_ARCHIVE_TYPE          auto|zip|tar|tgz|tar.gz (default: auto)
#   ETAX_CAB_FETCH_ROOT_DIR        extraction root (default: /tmp/etax-cab-input)
#   ETAX_CAB_FALLBACK_INPUT_DIR    fallback input dir (default: tools/etax/fixtures)
#
# Output:
#   status=ok|skip|error
#   reason=<message>
#   input_dir=<directory>

to_bool() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "1" || "$value" == "true" || "$value" == "yes" ]]
}

print_result() {
  local status="$1"
  local reason="$2"
  local input_dir="$3"
  echo "status=$status"
  echo "reason=$reason"
  echo "input_dir=$input_dir"
}

source_url="${ETAX_CAB_SOURCE_URL:-}"
source_required="${ETAX_CAB_SOURCE_REQUIRED:-false}"
expected_sha256="${ETAX_CAB_SOURCE_SHA256:-}"
archive_type="${ETAX_CAB_ARCHIVE_TYPE:-auto}"
fetch_root_dir="${ETAX_CAB_FETCH_ROOT_DIR:-/tmp/etax-cab-input}"
fallback_input_dir="${ETAX_CAB_FALLBACK_INPUT_DIR:-tools/etax/fixtures}"

if [[ -z "$source_url" ]]; then
  if to_bool "$source_required"; then
    print_result "error" "ETAX_CAB_SOURCE_URL is required but empty" "$fallback_input_dir"
    exit 1
  fi
  print_result "skip" "ETAX_CAB_SOURCE_URL is not set; fallback input is used" "$fallback_input_dir"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  print_result "error" "curl command is not available" "$fallback_input_dir"
  exit 1
fi

mkdir -p "$fetch_root_dir"

archive_path="$fetch_root_dir/cab-input.archive"
extract_dir="$fetch_root_dir/extracted"

rm -f "$archive_path"
rm -rf "$extract_dir"
mkdir -p "$extract_dir"

curl -fsSL "$source_url" -o "$archive_path"

if [[ -n "$expected_sha256" ]]; then
  if ! command -v shasum >/dev/null 2>&1; then
    print_result "error" "shasum command is not available for SHA-256 verification" "$fallback_input_dir"
    exit 1
  fi
  actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    print_result \
      "error" \
      "SHA-256 mismatch (expected=$expected_sha256 actual=$actual_sha256)" \
      "$fallback_input_dir"
    exit 1
  fi
fi

archive_type_lc="$(printf '%s' "$archive_type" | tr '[:upper:]' '[:lower:]')"
if [[ "$archive_type_lc" == "auto" ]]; then
  case "$source_url" in
    *.tar.gz|*.tgz) archive_type_lc="tar.gz" ;;
    *.tar) archive_type_lc="tar" ;;
    *.zip) archive_type_lc="zip" ;;
    *)
      print_result "error" "archive type is unknown; set ETAX_CAB_ARCHIVE_TYPE explicitly" "$fallback_input_dir"
      exit 1
      ;;
  esac
fi

case "$archive_type_lc" in
  zip)
    if ! command -v unzip >/dev/null 2>&1; then
      print_result "error" "unzip command is not available" "$fallback_input_dir"
      exit 1
    fi
    unzip -qq "$archive_path" -d "$extract_dir"
    ;;
  tgz|tar.gz)
    tar -xzf "$archive_path" -C "$extract_dir"
    ;;
  tar)
    tar -xf "$archive_path" -C "$extract_dir"
    ;;
  *)
    print_result "error" "unsupported archive type: $archive_type_lc" "$fallback_input_dir"
    exit 1
    ;;
esac

# If archive has a single top-level directory, use it as input root.
single_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
root_dir_count="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
file_count="$(find "$extract_dir" -type f | wc -l | tr -d ' ')"

if [[ "$file_count" -eq 0 ]]; then
  print_result "error" "archive extracted but no files were found" "$fallback_input_dir"
  exit 1
fi

input_dir="$extract_dir"
if [[ "$root_dir_count" -eq 1 && -n "$single_root" ]]; then
  input_dir="$single_root"
fi

print_result "ok" "CAB input fetched successfully" "$input_dir"
