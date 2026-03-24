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
evidence_dir="${RELEASE_QUALITY_EVIDENCE_DIR:-}"
mode="${RELEASE_QUALITY_MODE:-test}"
configuration="${RELEASE_QUALITY_CONFIGURATION:-Debug}"
destination_override="${RELEASE_QUALITY_DESTINATION:-}"
release_head_sha="${RELEASE_QUALITY_HEAD_SHA:-${GITHUB_SHA:-}}"
release_run_id="${RELEASE_QUALITY_RUN_ID:-${GITHUB_RUN_ID:-}}"
release_run_url="${RELEASE_QUALITY_RUN_URL:-}"

to_repo_relative_path() {
  local target_path="$1"
  case "$target_path" in
    "$REPO_ROOT"/*)
      printf '%s\n' "${target_path#"$REPO_ROOT"/}"
      ;;
    *)
      printf '%s\n' "$target_path"
      ;;
  esac
}

if [[ -z "$lane" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_LANE is required"
  exit 1
fi

if [[ -z "$artifact_dir" ]]; then
  artifact_dir="/tmp/release-quality/$lane"
fi

if [[ "$mode" != "test" && "$mode" != "build" && "$mode" != "archive" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_MODE must be test|build|archive"
  exit 1
fi

if [[ "$mode" == "test" && -z "$simulator_device" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_SIMULATOR_DEVICE is required for test mode"
  exit 1
fi

if [[ "$mode" == "test" && -z "$only_testing" ]]; then
  echo "status=error"
  echo "reason=RELEASE_QUALITY_ONLY_TESTING is required for test mode"
  exit 1
fi

if [[ -z "$derived_data_path" ]]; then
  derived_data_path="$artifact_dir/DerivedData"
fi

if [[ -z "$release_head_sha" ]]; then
  release_head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
fi
if [[ -z "$release_head_sha" ]]; then
  release_head_sha="unknown"
fi
if [[ -z "$release_run_id" ]]; then
  release_run_id="local"
fi
if [[ -z "$release_run_url" ]]; then
  if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
    release_run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  else
    release_run_url="local"
  fi
fi

mkdir -p "$artifact_dir"

result_bundle_path="$artifact_dir/$lane.xcresult"
log_path="$artifact_dir/xcodebuild.log"
summary_path="$artifact_dir/summary.md"
metrics_path="$artifact_dir/performance_metrics.txt"
archive_path="$artifact_dir/${scheme_name}.xcarchive"

rm -rf "$result_bundle_path"
rm -rf "$archive_path"
rm -f "$metrics_path"

command=(xcodebuild)

case "$mode" in
  test)
    command+=(
      test
      -project "$project_path"
      -scheme "$scheme_name"
      -configuration "$configuration"
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
    ;;
  build)
    command+=(
      build
      -project "$project_path"
      -scheme "$scheme_name"
      -configuration "$configuration"
      -derivedDataPath "$derived_data_path"
      -destination "${destination_override:-generic/platform=iOS}"
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
    )
    ;;
  archive)
    command+=(
      archive
      -project "$project_path"
      -scheme "$scheme_name"
      -configuration "$configuration"
      -derivedDataPath "$derived_data_path"
      -archivePath "$archive_path"
      -destination "${destination_override:-generic/platform=iOS}"
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
    )
    ;;
esac

set +e
UPDATE_GOLDEN_SNAPSHOTS="$update_golden" "${command[@]}" 2>&1 | tee "$log_path"
exit_code=${PIPESTATUS[0]}
set -e

status="ok"
reason="xcodebuild $mode succeeded"
if [[ "$exit_code" -ne 0 ]]; then
  status="error"
  reason="xcodebuild $mode failed"
fi

test_summary="n/a"
if [[ "$mode" == "test" ]]; then
  test_summary="$(grep -Eo 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$log_path" | tail -n 1 || true)"
  if [[ -z "$test_summary" ]]; then
    test_summary="not-found"
  fi
fi

if [[ "$mode" == "test" ]]; then
  grep -Eo 'performance\.[A-Za-z0-9_]+\.seconds=[0-9]+(\.[0-9]+)?' "$log_path" > "$metrics_path" || true
fi

{
  echo "## $lane"
  echo "- status: $status"
  echo "- reason: $reason"
  echo "- mode: $mode"
  echo "- configuration: $configuration"
  echo "- head_sha: $release_head_sha"
  echo "- run_id: $release_run_id"
  echo "- run_url: $release_run_url"
  echo "- test_summary: $test_summary"
  if [[ -n "$simulator_device" ]]; then
    echo "- simulator_device: $simulator_device"
  fi
  if [[ "$mode" == "test" ]]; then
    echo "- xcresult: $result_bundle_path"
  fi
  if [[ "$mode" == "archive" ]]; then
    echo "- archive: $archive_path"
  fi
  echo "- log: $log_path"
  if [[ -s "$metrics_path" ]]; then
    echo "- performance_metrics:"
    while IFS= read -r line; do
      echo "  - $line"
    done < "$metrics_path"
  fi
} > "$summary_path"

evidence_latest_lane_path=""
evidence_lane_path=""
if [[ -n "$evidence_dir" ]]; then
  mkdir -p "$evidence_dir"

  generated_at="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %z')"
  summary_rel="$(to_repo_relative_path "$summary_path")"
  log_rel="$(to_repo_relative_path "$log_path")"
  xcresult_rel="$(to_repo_relative_path "$result_bundle_path")"
  metrics_rel="$(to_repo_relative_path "$metrics_path")"
  archive_rel="$(to_repo_relative_path "$archive_path")"

  evidence_latest_lane_path="$evidence_dir/latest-lane.md"
  evidence_lane_path="$evidence_dir/${lane}.md"

  {
    echo "# Release Quality Evidence"
    echo ""
    echo "- generated_at: $generated_at"
    echo "- lane: $lane"
    echo "- status: $status"
    echo "- reason: $reason"
    echo "- mode: $mode"
    echo "- configuration: $configuration"
    echo "- head_sha: $release_head_sha"
    echo "- run_id: $release_run_id"
    echo "- run_url: $release_run_url"
    if [[ -n "$simulator_device" ]]; then
      echo "- simulator_device: $simulator_device"
    fi
    echo "- test_summary: $test_summary"
    echo "- summary_path: $summary_rel"
    echo "- log_path: $log_rel"
    if [[ "$mode" == "test" ]]; then
      echo "- xcresult_path: $xcresult_rel"
      echo "- metrics_path: $metrics_rel"
    else
      echo "- xcresult_path: n/a"
      echo "- metrics_path: n/a"
    fi
    if [[ "$mode" == "archive" ]]; then
      echo "- archive_path: $archive_rel"
    fi
  } > "$evidence_latest_lane_path"

  cp "$evidence_latest_lane_path" "$evidence_lane_path"
fi

echo "status=$status"
echo "reason=$reason"
echo "mode=$mode"
echo "configuration=$configuration"
echo "head_sha=$release_head_sha"
echo "run_id=$release_run_id"
echo "run_url=$release_run_url"
echo "test_summary=$test_summary"
echo "log_path=$log_path"
if [[ "$mode" == "test" ]]; then
  echo "xcresult_path=$result_bundle_path"
else
  echo "xcresult_path=n/a"
fi
if [[ "$mode" == "archive" ]]; then
  echo "archive_path=$archive_path"
fi
echo "summary_path=$summary_path"
if [[ "$mode" == "test" ]]; then
  echo "metrics_path=$metrics_path"
else
  echo "metrics_path=n/a"
fi
if [[ -n "$evidence_latest_lane_path" ]]; then
  echo "evidence_latest_lane_path=$evidence_latest_lane_path"
  echo "evidence_lane_path=$evidence_lane_path"
fi

if [[ "$exit_code" -ne 0 ]]; then
  exit "$exit_code"
fi
