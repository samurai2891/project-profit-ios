#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

lane="${RELEASE_QUALITY_LANE:-}"
artifact_dir="${RELEASE_QUALITY_ARTIFACTS_DIR:-}"
simulator_device="${RELEASE_QUALITY_SIMULATOR_DEVICE:-}"
only_testing="${RELEASE_QUALITY_ONLY_TESTING:-}"
project_path="${RELEASE_QUALITY_PROJECT:-ProjectProfit.xcodeproj}"
scheme_name="${RELEASE_QUALITY_SCHEME:-ProjectProfit}"
derived_data_path="${RELEASE_QUALITY_DERIVED_DATA_PATH:-}"
update_golden="${RELEASE_QUALITY_UPDATE_GOLDEN:-0}"

if [[ -z "$lane" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_LANE is required"
  exit 1
fi

if [[ -z "$artifact_dir" ]]; then
  artifact_dir="/tmp/release-quality/$lane"
fi

if [[ -z "$simulator_device" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_SIMULATOR_DEVICE is required"
  exit 1
fi

if [[ -z "$only_testing" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_ONLY_TESTING is required"
  exit 1
fi

if [[ -z "$derived_data_path" ]]; then
  derived_data_path="$artifact_dir/DerivedData"
fi

mkdir -p "$artifact_dir"

result_bundle_path="$artifact_dir/$lane.xcresult"
log_path="$artifact_dir/xcodebuild.log"
summary_path="$artifact_dir/summary.md"
metrics_path="$artifact_dir/performance_metrics.txt"

rm -rf "$result_bundle_path"

command=(
  xcodebuild test
  -project "$project_path"
  -scheme "$scheme_name"
  -destination "platform=iOS Simulator,name=$simulator_device"
  -derivedDataPath "$derived_data_path"
  -resultBundlePath "$result_bundle_path"
  -parallel-testing-enabled NO
)

while IFS= read -r target; do
  if [[ -n "$target" ]]; then
    command+=("-only-testing:$target")
  fi
done <<< "$only_testing"

set +e
UPDATE_GOLDEN_SNAPSHOTS="$update_golden" "${command[@]}" 2>&1 | tee "$log_path"
exit_code=${PIPESTATUS[0]}
set -e

status="ok"
reason="xcodebuild test succeeded"
if [[ "$exit_code" -ne 0 ]]; then
  status="error"
  reason="xcodebuild test failed"
fi

test_summary="$(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$log_path" | tail -n 1 || true)"
if [[ -z "$test_summary" ]]; then
  test_summary="not-found"
fi

grep -Eo 'performance\.[A-Za-z0-9_]+\.seconds=[0-9]+(\.[0-9]+)?' "$log_path" > "$metrics_path" || true

{
  echo "## $lane"
  echo "- status: $status"
  echo "- reason: $reason"
  echo "- test_summary: $test_summary"
  echo "- simulator_device: $simulator_device"
  echo "- xcresult: $result_bundle_path"
  echo "- log: $log_path"
  if [[ -s "$metrics_path" ]]; then
    echo "- performance_metrics:"
    while IFS= read -r line; do
      echo "  - $line"
    done < "$metrics_path"
  fi
} > "$summary_path"

echo "status=$status"
echo "reason=$reason"
echo "test_summary=$test_summary"
echo "log_path=$log_path"
echo "xcresult_path=$result_bundle_path"
echo "summary_path=$summary_path"
echo "metrics_path=$metrics_path"

if [[ "$exit_code" -ne 0 ]]; then
  exit "$exit_code"
fi
