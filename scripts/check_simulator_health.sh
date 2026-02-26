#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/check_simulator_health.sh
#
# Output (stdout):
#   status=ok|warn|error
#   reason=<message>
#   simulator_device=<device name when status=ok>
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

  echo "status=$status"
  echo "reason=$reason"
  if [[ -n "$device" ]]; then
    echo "simulator_device=$device"
  fi
}

if ! command -v xcrun >/dev/null 2>&1; then
  print_result "error" "xcrun command is not available"
  exit 1
fi

runtime_list="$(xcrun simctl list runtimes 2>/dev/null || true)"
if ! printf '%s\n' "$runtime_list" | grep -q '^iOS'; then
  print_result "error" "No iOS simulator runtime found"
  exit 1
fi

device="$(
  xcrun simctl list devices available 2>/dev/null | awk '
    /^-- iOS/ { ios = 1; next }
    /^-- / { ios = 0 }
    ios && /iPhone/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/ \(.*/, "", line)
      print line
      exit
    }
  '
)"

device="$(trim "$device")"

fallback_used="false"

if [[ -z "$device" ]]; then
  # fallback parser for environments where simctl output format differs
  device="$(
    xcrun xctrace list devices 2>&1 | awk '
      /iPhone/ {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/ \(.*/, "", line)
        sub(/ Simulator$/, "", line)
        print line
        exit
      }
    '
  )"
  device="$(trim "$device")"
  if [[ -n "$device" ]]; then
    fallback_used="true"
  fi
fi

if [[ -z "$device" ]]; then
  print_result "error" "No available iPhone simulator device found"
  exit 1
fi

if [[ "$fallback_used" == "true" ]]; then
  print_result "warn" "Simulator health check passed via xctrace fallback" "$device"
  exit 0
fi

print_result "ok" "Simulator health check passed" "$device"
