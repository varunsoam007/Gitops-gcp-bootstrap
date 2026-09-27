#!/usr/bin/env bash
# chart-rollout-report.sh — Report chart version rollout status across environments
#
# Scans kustomization.yaml files per environment to show which chart version
# each cluster is using, highlighting mid-cycle rollouts.
#
# Usage:
#   ./chart-rollout-report.sh                           # Table report to stdout
#   ./chart-rollout-report.sh --json                    # JSON output
#   ./chart-rollout-report.sh --name alloy              # Check a single chart
#   ./chart-rollout-report.sh --rolling-only            # Show only mid-rollout charts
#   ./chart-rollout-report.sh --report-dir /tmp/out     # Write both table + JSON files
#
# Dependencies: yq (https://github.com/mikefarah/yq v4+)
# Exit codes:  0 = all consistent, 1 = rollouts in progress, 2 = error
#
# No network calls — purely filesystem scan.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY="${SCRIPT_DIR}/chart-registry.yaml"

# ── Environments (in rollout order) ──────────────────────────────────────────
ENVS=(devm-k01 tstm-k01 prdm-k01 mgt-k01)
ENV_SHORT=(devm tstm prdm mgt)

# ── Defaults ─────────────────────────────────────────────────────────────────
OUTPUT_FORMAT="table"
FILTER_NAME=""
ROLLING_ONLY=false
REPORT_DIR=""
ROLLING_COUNT=0
DRIFT_COUNT=0
CONSISTENT_COUNT=0
CHARTS_MATCHED=0

# ── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)          OUTPUT_FORMAT="json"; shift ;;
    --name)          FILTER_NAME="$2"; shift 2 ;;
    --rolling-only)  ROLLING_ONLY=true; shift ;;
    --report-dir)    REPORT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--json] [--name <chart>] [--rolling-only] [--report-dir DIR]"
      echo ""
      echo "Options:"
      echo "  --json             Output as JSON array"
      echo "  --name NAME        Check a single chart by name"
      echo "  --rolling-only     Show only charts with mid-cycle rollout"
      echo "  --report-dir DIR   Write both rollout-report.txt and rollout-report.json to DIR"
      echo ""
      echo "Exit codes: 0 = all consistent, 1 = rollouts in progress, 2 = error"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--json] [--name <chart>] [--rolling-only] [--report-dir DIR]" >&2
      exit 2
      ;;
  esac
done

# ── Dependency checks ────────────────────────────────────────────────────────
if ! command -v yq &>/dev/null; then
  echo "Error: 'yq' is required but not installed." >&2
  echo "Install: https://github.com/mikefarah/yq#install" >&2
  exit 2
fi

if [[ ! -f "${REGISTRY}" ]]; then
  echo "Error: Chart registry not found at ${REGISTRY}" >&2
  exit 2
fi

# ── Pre-load registry data ──────────────────────────────────────────────────
# TSV: name \t directory \t version \t internal
REGISTRY_DATA=$(yq -r '.charts[] | [
  .name // "",
  .directory // "",
  .version // "",
  .internal // false
] | @tsv' "${REGISTRY}")

# ── Build env version maps ──────────────────────────────────────────────────
# For each env, extract all helmCharts[].name from kustomization files.
# Store as associative arrays: ENV_DIRS_<env>[directory] = 1
declare -A DEVM_DIRS=()
declare -A TSTM_DIRS=()
declare -A PRDM_DIRS=()
declare -A MGT_DIRS=()

load_env_dirs() {
  local env="$1"
  local -n dir_map="$2"
  local kust_file

  for kust_file in "${REPO_ROOT}"/apps/*/envs/"${env}"/kustomization.yaml; do
    [[ -f "$kust_file" ]] || continue
    local dirs
    dirs=$(yq -r '.helmCharts[].name' "$kust_file" 2>/dev/null) || continue
    while IFS= read -r dir; do
      if [[ -n "$dir" ]]; then dir_map["$dir"]=1; fi
    done <<< "$dirs"
  done
}

load_env_dirs "devm-k01" DEVM_DIRS
load_env_dirs "tstm-k01" TSTM_DIRS
load_env_dirs "prdm-k01" PRDM_DIRS
load_env_dirs "mgt-k01"  MGT_DIRS

# ── Version extraction from directory name ───────────────────────────────────
# Given a registry entry (name + directory), find which version an env is using.
# Match by checking if the env has a directory that starts with the same prefix.
#
# Build a prefix map: for each registry entry, compute the directory prefix
# (everything before the version). Then for each env, find directories matching
# that prefix and extract the version suffix.

get_env_version() {
  local registry_dir="$1" registry_version="$2" registry_name="$3"
  local -n env_dirs="$4"

  # Fast path: exact match means env is on the vendored version
  if [[ -n "${env_dirs[$registry_dir]+_}" ]]; then
    echo "${registry_version}"
    return
  fi

  # Compute prefix: directory minus the version suffix
  # e.g., "alloy-1.2.1" → prefix "alloy-", "jetstack-cert-manager-v1.18.1" → "jetstack-cert-manager-"
  local prefix="${registry_dir%-${registry_version}}"
  # Handle v-prefixed versions in directory names (e.g., dragonfly-v1.36.0 where version is "v1.36.0")
  if [[ "${prefix}" == "${registry_dir}" ]]; then
    # Didn't match — try without the v prefix
    local ver_no_v="${registry_version#v}"
    prefix="${registry_dir%-v${ver_no_v}}"
    if [[ "${prefix}" == "${registry_dir}" ]]; then
      prefix="${registry_dir%-${ver_no_v}}"
    fi
  fi
  prefix="${prefix}-"

  # Search env directories for one matching this prefix
  for dir in "${!env_dirs[@]}"; do
    if [[ "$dir" == "${prefix}"* ]]; then
      # Extract version: everything after the prefix
      local ver="${dir#${prefix}}"
      echo "$ver"
      return
    fi
  done

  # Not found in this env
  echo ""
}

# ── Determine whether env should have this chart ────────────────────────────
# Check if the app's env directory exists (not just if it uses this chart)
env_has_app() {
  local registry_name="$1" env="$2"

  # The app directory under apps/ can differ from the chart name.
  # We need to find which app directory uses this chart.
  # We've already loaded all dirs per env, so if ANY version of this chart
  # prefix is present, the env has the app.
  # If not, we check if the env directory even exists for possible
  # Kustomize-only apps.
  return 0  # Handled by version being empty in get_env_version
}

# ── Output control ──────────────────────────────────────────────────────────
WANT_TABLE=false
WANT_JSON=false
if [[ -n "${REPORT_DIR}" ]]; then
  WANT_TABLE=true
  WANT_JSON=true
elif [[ "${OUTPUT_FORMAT}" == "json" ]]; then
  WANT_JSON=true
else
  WANT_TABLE=true
fi

JSON_RESULTS="["
JSON_FIRST=true

# ── Table helper ──────────────────────────────────────────────────────────────
# Print a colored, padded table column.  Color escapes are printed outside the
# %-Ns specifier so they don't affect visible-width padding.
pcol() { printf "%b%-${1}s%b" "$2" "$3" "${RESET}"; }

# ── Table header ─────────────────────────────────────────────────────────────
if ${WANT_TABLE}; then
  echo ""
  printf "%b%-28s %-12s %-12s %-12s %-12s %-12s %-14s%b\n" \
    "${BOLD}" "CHART" "VENDORED" "devm" "tstm" "prdm" "mgt" "STATUS" "${RESET}"
  printf "%-28s %-12s %-12s %-12s %-12s %-12s %-14s\n" \
    "----------------------------" "------------" "------------" "------------" "------------" "------------" "--------------"
fi

# ── Main loop ────────────────────────────────────────────────────────────────
while IFS=$'\t' read -r name directory version internal; do
  # Apply name filter
  if [[ -n "${FILTER_NAME}" && "${name}" != "${FILTER_NAME}" ]]; then
    continue
  fi

  CHARTS_MATCHED=$((CHARTS_MATCHED + 1))

  # Skip internal charts
  if [[ "${internal}" == "true" ]]; then
    if ${WANT_TABLE} && ! ${ROLLING_ONLY}; then
      printf "%-28s %-12s " "${name}" "${version}"
      pcol 12 "${DIM}" "-"; printf " "
      pcol 12 "${DIM}" "-"; printf " "
      pcol 12 "${DIM}" "-"; printf " "
      pcol 12 "${DIM}" "-"; printf " "
      pcol 14 "${CYAN}" "Internal"
      printf "\n"
    fi
    if ${WANT_JSON}; then
      ${JSON_FIRST} || JSON_RESULTS+=","
      JSON_FIRST=false
      JSON_RESULTS+="{\"name\":\"${name}\",\"vendored\":\"${version}\",\"devm\":\"-\",\"tstm\":\"-\",\"prdm\":\"-\",\"mgt\":\"-\",\"status\":\"internal\"}"
    fi
    continue
  fi

  # Get version in each environment
  ver_devm=$(get_env_version "$directory" "$version" "$name" DEVM_DIRS)
  ver_tstm=$(get_env_version "$directory" "$version" "$name" TSTM_DIRS)
  ver_prdm=$(get_env_version "$directory" "$version" "$name" PRDM_DIRS)
  ver_mgt=$(get_env_version "$directory" "$version" "$name" MGT_DIRS)

  # Normalize for display: empty = N/A (not deployed to that env)
  disp_devm="${ver_devm:-N/A}"
  disp_tstm="${ver_tstm:-N/A}"
  disp_prdm="${ver_prdm:-N/A}"
  disp_mgt="${ver_mgt:-N/A}"

  # Determine status
  # Collect unique non-empty versions
  declare -a deployed_vers=()
  for v in "$ver_devm" "$ver_tstm" "$ver_prdm" "$ver_mgt"; do
    if [[ -n "$v" ]]; then deployed_vers+=("$v"); fi
  done

  unique_vers=($(printf '%s\n' "${deployed_vers[@]}" | sort -u))
  status="consistent"

  if [[ ${#unique_vers[@]} -eq 0 ]]; then
    status="not-deployed"
  elif [[ ${#unique_vers[@]} -eq 1 ]]; then
    # All deployed envs on same version
    local_ver="${unique_vers[0]}"
    norm_vendored="${version#v}"
    norm_local="${local_ver#v}"
    if [[ "${norm_vendored}" == "${norm_local}" ]]; then
      status="consistent"
      CONSISTENT_COUNT=$((CONSISTENT_COUNT + 1))
    else
      # All envs match each other but differ from registry — registry stale?
      status="drift"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    fi
  else
    # Multiple versions across environments — mid-rollout
    status="rolling"
    # Find which envs are behind
    behind_envs=""
    for i in "${!ENVS[@]}"; do
      local_v=""
      case $i in
        0) local_v="$ver_devm" ;;
        1) local_v="$ver_tstm" ;;
        2) local_v="$ver_prdm" ;;
        3) local_v="$ver_mgt" ;;
      esac
      if [[ -n "$local_v" ]]; then
        norm_v="${local_v#v}"
        norm_vendored="${version#v}"
        if [[ "${norm_v}" != "${norm_vendored}" ]]; then
          behind_envs+="${ENV_SHORT[$i]} "
        fi
      fi
    done
    ROLLING_COUNT=$((ROLLING_COUNT + 1))
  fi

  unset deployed_vers unique_vers

  # Apply rolling-only filter
  if ${ROLLING_ONLY} && [[ "${status}" != "rolling" && "${status}" != "drift" ]]; then
    continue
  fi

  # Determine color for each env version
  ver_color() {
    local ver="$1" vendored="$2"
    if [[ "$ver" == "N/A" ]]; then   echo "${DIM}"
    elif [[ "${ver#v}" == "${vendored#v}" ]]; then echo "${GREEN}"
    else echo "${YELLOW}"
    fi
  }

  c_devm=$(ver_color "$disp_devm" "$version")
  c_tstm=$(ver_color "$disp_tstm" "$version")
  c_prdm=$(ver_color "$disp_prdm" "$version")
  c_mgt=$(ver_color "$disp_mgt" "$version")

  # Determine status color
  case "$status" in
    consistent)    c_status="${GREEN}" ;;
    rolling)       c_status="${YELLOW}" ;;
    drift)         c_status="${RED}" ;;
    not-deployed)  c_status="${DIM}" ;;
    *)             c_status="" ;;
  esac

  # Status text (plain, no escape codes)
  case "$status" in
    consistent)    status_text="Consistent" ;;
    drift)         status_text="Drift" ;;
    not-deployed)  status_text="Not deployed" ;;
    rolling)
      behind_text=""
      if [[ -n "${behind_envs}" ]]; then
        behind_text=" (${behind_envs% } behind)"
      fi
      status_text="Rolling${behind_text}" ;;
    *)             status_text="$status" ;;
  esac

  # Output
  if ${WANT_TABLE}; then
    printf "%-28s %-12s " "${name}" "${version}"
    pcol 12 "$c_devm" "$disp_devm"; printf " "
    pcol 12 "$c_tstm" "$disp_tstm"; printf " "
    pcol 12 "$c_prdm" "$disp_prdm"; printf " "
    pcol 12 "$c_mgt"  "$disp_mgt";  printf " "
    pcol 14 "$c_status" "$status_text"
    printf "\n"
  fi

  if ${WANT_JSON}; then
    ${JSON_FIRST} || JSON_RESULTS+=","
    JSON_FIRST=false
    JSON_RESULTS+="{\"name\":\"${name}\",\"vendored\":\"${version}\",\"devm\":\"${disp_devm}\",\"tstm\":\"${disp_tstm}\",\"prdm\":\"${disp_prdm}\",\"mgt\":\"${disp_mgt}\",\"status\":\"${status}\"}"
  fi
done <<< "$REGISTRY_DATA"

JSON_RESULTS+="]"

# ── Summary / output ─────────────────────────────────────────────────────────
CHART_COUNT=${CHARTS_MATCHED}

print_table_summary() {
  echo ""
  echo "────────────────────────────────────────────────────────────────────────────────────────"
  echo -e "Charts checked: ${BOLD}${CHART_COUNT}${RESET}  |  " \
    "Consistent: ${GREEN}${CONSISTENT_COUNT}${RESET}  |  " \
    "Rolling: ${YELLOW}${ROLLING_COUNT}${RESET}  |  " \
    "Drift: ${RED}${DRIFT_COUNT}${RESET}"
  echo ""
  if [[ ${ROLLING_COUNT} -gt 0 ]]; then
    echo "Charts with in-progress rollouts need remaining environments updated."
    echo "Check rollout status:  ./chart-rollout-report.sh --rolling-only"
  fi
  if [[ ${DRIFT_COUNT} -gt 0 ]]; then
    echo -e "${RED}Drift detected: environments have versions not matching chart-registry.yaml.${RESET}"
    echo "Update chart-registry.yaml or environment kustomization files to resolve."
  fi
}

if [[ -n "${REPORT_DIR}" ]]; then
  mkdir -p "${REPORT_DIR}"
  print_table_summary
  echo "${JSON_RESULTS}" > "${REPORT_DIR}/rollout-report.json"
  echo ""
  echo "Wrote ${REPORT_DIR}/rollout-report.json"
elif [[ "${OUTPUT_FORMAT}" == "json" ]]; then
  echo "${JSON_RESULTS}"
else
  print_table_summary
fi

# Exit code
if [[ ${DRIFT_COUNT} -gt 0 ]]; then
  exit 2
elif [[ ${ROLLING_COUNT} -gt 0 ]]; then
  exit 1
else
  exit 0
fi
