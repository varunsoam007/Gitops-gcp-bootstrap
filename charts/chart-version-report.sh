#!/usr/bin/env bash
# chart-version-report.sh — Compare vendored Helm chart versions against upstream latest
#
# Usage:
#   ./chart-version-report.sh                           # Table report to stdout
#   ./chart-version-report.sh --json                    # JSON output
#   ./chart-version-report.sh --name alloy              # Check a single chart
#   ./chart-version-report.sh --outdated                # Show only charts with updates available
#   ./chart-version-report.sh --report-dir /tmp/out     # Write both table + JSON files
#
# Dependencies: helm, yq (https://github.com/mikefarah/yq v4+)
# Exit codes:  0 = all up-to-date, 1 = updates available, 2 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/chart-registry.yaml"

# ── Defaults ─────────────────────────────────────────────────────────────────
OUTPUT_FORMAT="table"
FILTER_NAME=""
OUTDATED_ONLY=false
REPORT_DIR=""
UPDATES_FOUND=0
ERRORS=0
CHARTS_MATCHED=0

# ── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)        OUTPUT_FORMAT="json"; shift ;;
    --name)        FILTER_NAME="$2"; shift 2 ;;
    --outdated)    OUTDATED_ONLY=true; shift ;;
    --report-dir)  REPORT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--json] [--name <chart>] [--outdated] [--report-dir DIR]"
      echo ""
      echo "Options:"
      echo "  --json            Output as JSON array"
      echo "  --name NAME       Check a single chart by name"
      echo "  --outdated        Show only charts with updates available"
      echo "  --report-dir DIR  Write both chart-report.txt and chart-report.json to DIR"
      echo ""
      echo "Exit codes: 0 = all up-to-date, 1 = updates available, 2 = error"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--json] [--name <chart>] [--outdated]" >&2
      exit 2
      ;;
  esac
done

# ── Dependency checks ────────────────────────────────────────────────────────
check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' is required but not installed." >&2
    echo "Install: $2" >&2
    exit 2
  fi
}

check_dependency helm "https://helm.sh/docs/intro/install/"
check_dependency yq "https://github.com/mikefarah/yq#install"

if [[ ! -f "${REGISTRY}" ]]; then
  echo "Error: Chart registry not found at ${REGISTRY}" >&2
  exit 2
fi

# ── Helm repo cache ─────────────────────────────────────────────────────────
# Track which repos we've already added to avoid duplicate adds
declare -A REPOS_ADDED=()

ensure_repo() {
  local alias="$1" url="$2"
  if [[ -z "${REPOS_ADDED[$alias]+_}" ]]; then
    helm repo add "$alias" "$url" --force-update &>/dev/null 2>&1 || true
    REPOS_ADDED[$alias]=1
  fi
}

# ── Version comparison ───────────────────────────────────────────────────────
# Strip leading 'v' for comparison
normalize_version() {
  echo "${1#v}"
}

# ── Get latest version from upstream ─────────────────────────────────────────
get_latest_helm() {
  local alias="$1" chart="$2"
  ensure_repo "$alias" "$3"
  # Get the latest version from the repo (repos updated in bulk below)
  local result
  result=$(helm search repo "${alias}/${chart}" --output json 2>/dev/null | \
    yq -p json -r '.[0].version' 2>/dev/null) || true
  # yq returns literal "null" for empty arrays — treat as empty
  if [[ "${result}" == "null" ]]; then result=""; fi
  echo "${result:-}"
}

get_latest_oci() {
  local repo="$1" chart="$2"
  # helm show chart fetches the latest version metadata from OCI
  local result
  result=$(helm show chart "${repo}/${chart}" 2>/dev/null | \
    yq -r '.version' 2>/dev/null) || true
  # yq returns literal "null" on parse failures — treat as empty
  if [[ "${result}" == "null" ]]; then result=""; fi
  echo "${result:-}"
}

# ── Pre-load all chart data in one yq call ───────────────────────────────────
# This avoids calling yq 8× per chart (224 calls for 28 charts).
# Instead we extract all fields as TSV in a single pass.
CHART_DATA=$(yq -r '.charts[] | [
  .name // "",
  .version // "",
  .type // "helm",
  .chart // .name // "",
  .internal // false,
  .localPatches // false,
  .repo // "",
  .repoAlias // ""
] | @tsv' "${REGISTRY}")

CHART_TOTAL=$(echo "$CHART_DATA" | wc -l)

# ── Add helm repos, then update once ─────────────────────────────────────────
# When --name is specified, only add the repo for that chart (much faster).
while IFS=$'\t' read -r _name _version _type _chart _internal _localPatches _repo _repoAlias; do
  if [[ -n "${FILTER_NAME}" && "${_name}" != "${FILTER_NAME}" ]]; then
    continue
  fi
  if [[ "${_type}" == "helm" && -n "${_repoAlias}" ]]; then
    ensure_repo "${_repoAlias}" "${_repo}"
  fi
done <<< "$CHART_DATA"

# Single bulk update is much faster than per-repo updates
if [[ ${#REPOS_ADDED[@]} -gt 0 ]]; then
  helm repo update &>/dev/null 2>&1 || true
fi

# ── Main ─────────────────────────────────────────────────────────────────────
# When --report-dir is set, always build both table + JSON in a single pass.
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

# Table header
if ${WANT_TABLE}; then
  echo ""
  printf "${BOLD}%-30s %-15s %-15s %-20s %-8s${RESET}\n" \
    "CHART" "CURRENT" "LATEST" "STATUS" "PATCHES"
  printf "%-30s %-15s %-15s %-20s %-8s\n" \
    "------------------------------" "---------------" "---------------" "--------------------" "--------"
fi

while IFS=$'\t' read -r name version type chart internal local_patches repo repo_alias; do
  # Apply name filter
  if [[ -n "${FILTER_NAME}" && "${name}" != "${FILTER_NAME}" ]]; then
    continue
  fi

  CHARTS_MATCHED=$((CHARTS_MATCHED + 1))

  # Skip internal charts
  if [[ "${internal}" == "true" ]]; then
    if ${WANT_TABLE} && [[ "${OUTDATED_ONLY}" == "false" ]]; then
      printf "%-30s %-15s %-15s ${CYAN}%-20s${RESET} %-8s\n" \
        "${name}" "${version}" "-" "Internal (skipped)" "-"
    fi
    if ${WANT_JSON}; then
      ${JSON_FIRST} || JSON_RESULTS+=","
      JSON_FIRST=false
      JSON_RESULTS+="{\"name\":\"${name}\",\"current\":\"${version}\",\"latest\":\"-\",\"status\":\"internal\",\"localPatches\":false}"
    fi
    continue
  fi

  # Fetch latest version
  latest=""
  case "${type}" in
    helm)
      latest=$(get_latest_helm "${repo_alias}" "${chart}" "${repo}")
      ;;
    oci)
      latest=$(get_latest_oci "${repo}" "${chart}")
      ;;
  esac

  # Determine status
  status="unknown"
  status_display=""
  patches_display="-"

  if [[ "${local_patches}" == "true" ]]; then
    patches_display="YES"
  fi

  if [[ -z "${latest}" ]]; then
    status="error"
    status_display="${RED}Fetch failed${RESET}"
    ERRORS=$((ERRORS + 1))
  else
    current_norm=$(normalize_version "${version}")
    latest_norm=$(normalize_version "${latest}")

    if [[ "${current_norm}" == "${latest_norm}" ]]; then
      status="up-to-date"
      status_display="${GREEN}Up-to-date${RESET}"
    else
      status="update-available"
      status_display="${YELLOW}Update → ${latest}${RESET}"
      UPDATES_FOUND=$((UPDATES_FOUND + 1))
    fi
  fi

  # Apply outdated filter
  if [[ "${OUTDATED_ONLY}" == "true" && "${status}" == "up-to-date" ]]; then
    continue
  fi

  # Output
  if ${WANT_TABLE}; then
    printf "%-30s %-15s %-15s %-20b %-8s\n" \
      "${name}" "${version}" "${latest:-?}" "${status_display}" "${patches_display}"
  fi

  if ${WANT_JSON}; then
    ${JSON_FIRST} || JSON_RESULTS+=","
    JSON_FIRST=false
    JSON_RESULTS+="{\"name\":\"${name}\",\"current\":\"${version}\",\"latest\":\"${latest:-unknown}\",\"status\":\"${status}\",\"localPatches\":${local_patches}}"
  fi
done <<< "$CHART_DATA"

JSON_RESULTS+="]"

# ── Summary / output ─────────────────────────────────────────────────────────
CHART_COUNT=${CHARTS_MATCHED}

print_table_summary() {
  echo ""
  echo "────────────────────────────────────────────────────────────────────"
  echo -e "Charts checked: ${BOLD}${CHART_COUNT}${RESET}  |  " \
    "Updates: ${YELLOW}${UPDATES_FOUND}${RESET}  |  " \
    "Errors: ${RED}${ERRORS}${RESET}"
  echo ""
  if [[ ${UPDATES_FOUND} -gt 0 ]]; then
    echo "To update a chart:  ./chart-downloader.sh --name <chart> [--version <version>]"
  fi
}

if [[ -n "${REPORT_DIR}" ]]; then
  # --report-dir: write both table + JSON, print table to stdout too
  mkdir -p "${REPORT_DIR}"
  print_table_summary
  echo "${JSON_RESULTS}" > "${REPORT_DIR}/chart-report.json"
  echo "Wrote ${REPORT_DIR}/chart-report.json"
elif [[ "${OUTPUT_FORMAT}" == "json" ]]; then
  echo "${JSON_RESULTS}"
else
  print_table_summary
fi

# Exit code
if [[ ${ERRORS} -gt 0 ]]; then
  exit 2
elif [[ ${UPDATES_FOUND} -gt 0 ]]; then
  exit 1
else
  exit 0
fi
