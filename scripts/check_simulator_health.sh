#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/check_simulator_health.sh
#
# Output (stdout):
#   status=ok|warn|error
#   reason=<message>
#   simulator_device=<device name when status=ok|warn>
#   simulator_id=<device UDID when status=ok|warn and available>
#
# Exit code:
#   0: status=ok|warn
#   1: status=error

trim() {
  local value="$1"
  # shellcheck disable=SC2001
  echo "$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
}

print_result() {
  local status="$1"
  local reason="$2"
  local device="${3:-}"
  local simulator_id="${4:-}"

  echo "status=$status"
  echo "reason=$reason"
  if [[ -n "$device" ]]; then
    echo "simulator_device=$device"
  fi
  if [[ -n "$simulator_id" ]]; then
    echo "simulator_id=$simulator_id"
  fi
}

normalize_list() {
  local csv="$1"
  printf '%s\n' "$csv" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | awk 'NF > 0'
}

is_coresimulator_unavailable() {
  local text="$1"
  printf '%s\n' "$text" | grep -qiE \
    'CoreSimulatorService connection became invalid|Unable to locate device set|Connection refused|simdiskimaged'
}

if ! command -v xcrun >/dev/null 2>&1; then
  print_result "error" "xcrun command is not available"
  exit 1
fi

runtime_list="$(xcrun simctl list runtimes 2>&1 || true)"
if is_coresimulator_unavailable "$runtime_list"; then
  print_result "error" "CoreSimulatorService is unavailable"
  exit 1
fi
if ! printf '%s\n' "$runtime_list" | grep -q '^iOS'; then
  print_result "error" "No iOS simulator runtime found"
  exit 1
fi

simctl_devices_output="$(xcrun simctl list devices available 2>&1 || true)"
if is_coresimulator_unavailable "$simctl_devices_output"; then
  print_result "error" "CoreSimulatorService is unavailable"
  exit 1
fi

preferred_devices_csv="${RELEASE_QUALITY_SIMULATOR_PREFERENCES:-iPhone 17 Pro,iPhone 17,iPhone 17 Pro Max,iPhone 16e,iPhone 16 Pro,iPhone 16}"
preferred_devices=()
while IFS= read -r preferred_line; do
  preferred_devices+=("$preferred_line")
done < <(normalize_list "$preferred_devices_csv")

ranked_devices=()
while IFS= read -r ranked_line; do
  ranked_devices+=("$ranked_line")
done < <(
  printf '%s\n' "$simctl_devices_output" | awk '
    function runtime_score(value, parts, major, minor) {
      split(value, parts, ".")
      major = parts[1] + 0
      minor = parts[2] + 0
      return major * 100 + minor
    }
    /^-- iOS/ {
      ios = 1
      runtime = $0
      sub(/^-- iOS /, "", runtime)
      sub(/ --$/, "", runtime)
      score = runtime_score(runtime)
      next
    }
    /^-- / { ios = 0 }
    ios && /iPhone/ {
      line = $0
      name = line
      sub(/^[[:space:]]+/, "", name)
      sub(/[[:space:]]+\([[:xdigit:]-]+\).*/, "", name)
      uuid = line
      sub(/^[^(]*\(/, "", uuid)
      sub(/\).*/, "", uuid)
      printf "%d|%s|%s\n", score, name, uuid
    }
  '
)

ranked_devices_count="${#ranked_devices[@]}"
if [[ "$ranked_devices_count" -gt 0 ]]; then
  IFS=$'\n' ranked_devices=($(printf '%s\n' "${ranked_devices[@]}" | sort -t'|' -k1,1nr -k2,2))
fi

device=""
simulator_id=""
fallback_used="false"

for preferred in "${preferred_devices[@]}"; do
  for entry in "${ranked_devices[@]}"; do
    ranked_name="${entry#*|}"
    ranked_name="${ranked_name%%|*}"
    if [[ "$ranked_name" == "$preferred" ]]; then
      device="$ranked_name"
      simulator_id="${entry##*|}"
      break 2
    fi
  done
done

if [[ -z "$device" && "$ranked_devices_count" -gt 0 ]]; then
  first_entry="${ranked_devices[0]}"
  device="${first_entry#*|}"
  device="${device%%|*}"
  simulator_id="${first_entry##*|}"
fi

if [[ -z "$device" ]]; then
  # fallback parser for environments where simctl output format differs
  fallback_device_info="$(
    xcrun xctrace list devices 2>&1 | awk '
      /iPhone/ {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]*\([^)]*\)[[:space:]]*$/, "", line)
        sub(/ Simulator$/, "", line)
        printf "%s|\n", line
        exit
      }
    '
  )"
  device="${fallback_device_info%%|*}"
  simulator_id="${fallback_device_info#*|}"
  device="$(trim "$device")"
  simulator_id="$(trim "$simulator_id")"
  if [[ -n "$device" ]]; then
    fallback_used="true"
  fi
fi

if [[ -z "$device" ]]; then
  print_result "error" "No available iPhone simulator device found"
  exit 1
fi

if [[ "$fallback_used" == "true" ]]; then
  print_result "warn" "Simulator health check passed via xctrace fallback" "$device" "$simulator_id"
  exit 0
fi

print_result "ok" "Simulator health check passed (deterministic preference selection)" "$device" "$simulator_id"
