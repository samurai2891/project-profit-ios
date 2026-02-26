#!/usr/bin/env bash
set -euo pipefail

artifact_dir="${1:-${ETAX_ARTIFACTS_DIR:-/tmp/etax-unit-lane}}"

summary_file="$artifact_dir/xsd_validation_summary.txt"
blue_log="$artifact_dir/xsd_blue_validation.log"
white_log="$artifact_dir/xsd_white_validation.log"
overlay_report="$artifact_dir/cab_overlay_2025.generated.report.json"
overlay_diff="$artifact_dir/TaxYear2025.overlay.diff.json"

extract_status() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    printf 'status=missing'
    return 0
  fi
  local status
  status="$(grep -Eo 'status=(ok|warn|error)' "$log_file" | tail -n 1 || true)"
  if [[ -z "$status" ]]; then
    printf 'status=unknown'
    return 0
  fi
  printf '%s' "$status"
}

echo "### e-Tax Lane Evidence"
echo "- artifact_dir: $artifact_dir"

echo ""
echo "#### XSD"
if [[ -f "$summary_file" ]]; then
  echo ""
  echo '```text'
  cat "$summary_file"
  echo '```'
else
  echo "- xsd summary file not found: $summary_file"
fi
echo "- blue xsd: $(extract_status "$blue_log")"
echo "- white xsd: $(extract_status "$white_log")"

echo ""
echo "#### CAB overlay report"
python3 - "$overlay_report" <<'PY'
import json
import os
import sys

path = sys.argv[1]
if not os.path.isfile(path):
    print(f"- overlay report not found: {path}")
    raise SystemExit(0)

with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

conflict_count = data.get("conflictCount", {})
print(f"- overlayItemCount: {data.get('overlayItemCount', 0)}")
print(f"- taxYearFieldCount: {data.get('taxYearFieldCount', 0)}")
print(f"- missingFieldCount: {data.get('missingFieldCount', 0)}")
print(f"- unresolvedIdrefCount: {data.get('unresolvedIdrefCount', 0)}")
print(f"- conflictCount.dataType: {conflict_count.get('dataType', 0)}")
print(f"- conflictCount.format: {conflict_count.get('format', 0)}")
print(f"- conflictCount.idref: {conflict_count.get('idref', 0)}")

facts = data.get("whiteInsuranceFacts") or []
if not facts:
    print("- whiteInsuranceFacts: none")
else:
    tags = ", ".join(str(item.get("xmlTag", "")) for item in facts if item.get("xmlTag"))
    print(f"- whiteInsuranceFacts: {len(facts)} ({tags})")
PY

echo ""
echo "#### Overlay diff"
python3 - "$overlay_diff" <<'PY'
import json
import os
import sys

path = sys.argv[1]
if not os.path.isfile(path):
    print(f"- overlay diff not found: {path}")
    raise SystemExit(0)

with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

print(f"- changedFieldCount: {data.get('changedFieldCount', 0)}")
print(f"- addedCount: {data.get('addedCount', 0)}")
print(f"- removedCount: {data.get('removedCount', 0)}")
PY

echo ""
echo "#### Files"
for path in \
  "$summary_file" \
  "$blue_log" \
  "$white_log" \
  "$overlay_report" \
  "$overlay_diff"; do
  if [[ -f "$path" ]]; then
    echo "- [x] $path"
  else
    echo "- [ ] $path"
  fi
done
