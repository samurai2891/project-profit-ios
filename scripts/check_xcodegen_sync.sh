#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

project_spec="${XCODEGEN_SPEC_PATH:-project.yml}"
project_dir="${XCODEGEN_PROJECT_DIR:-ProjectProfit.xcodeproj}"

print_result() {
  local status="$1"
  local reason="$2"
  echo "status=$status"
  echo "reason=$reason"
}

if [[ ! -f "$project_spec" ]]; then
  print_result "error" "project spec not found: $project_spec"
  exit 1
fi

if [[ ! -d "$project_dir" ]]; then
  print_result "error" "xcodeproj not found: $project_dir"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  print_result "error" "xcodegen command is not available"
  exit 1
fi

set +e
xcodegen_output="$(xcodegen generate --spec "$project_spec" 2>&1)"
xcodegen_exit=$?
set -e

printf '%s\n' "$xcodegen_output"

if [[ "$xcodegen_exit" -ne 0 ]]; then
  print_result "error" "xcodegen generate failed"
  exit 1
fi

if ! git diff --quiet -- "$project_dir"; then
  echo "xcodegen sync check failed. changed files:"
  git status --short -- "$project_dir"
  print_result "error" "ProjectProfit.xcodeproj is out of sync with $project_spec"
  exit 1
fi

print_result "ok" "ProjectProfit.xcodeproj is in sync with $project_spec"
