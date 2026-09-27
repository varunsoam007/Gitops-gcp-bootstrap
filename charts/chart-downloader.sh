#!/usr/bin/env bash
# chart-downloader.sh — Download or update a vendored Helm chart
#
# Usage:
#   ./chart-downloader.sh --name alloy                          # Download latest version
#   ./chart-downloader.sh --name alloy --version 1.3.0          # Download specific version
#   ./chart-downloader.sh --name alloy --version 1.3.0 --force  # Overwrite existing
#   ./chart-downloader.sh --name alloy --dry-run                # Show what would happen
#
# The chart is looked up in chart-registry.yaml to determine the repo type and URL.
# After download, the registry file is updated with the new version and directory.
#
# Dependencies: helm, yq (https://github.com/mikefarah/yq v4+)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/chart-registry.yaml"

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

# ── Defaults ─────────────────────────────────────────────────────────────────
CHART_NAME=""
CHART_VERSION=""
FORCE=false
DRY_RUN=false

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     CHART_NAME="$2"; shift 2 ;;
    --version)  CHART_VERSION="$2"; shift 2 ;;
    --force)    FORCE=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: $0 --name <chart> [--version <version>] [--force] [--dry-run]"
      echo ""
      echo "Options:"
      echo "  --name NAME       Chart name as listed in chart-registry.yaml (required)"
      echo "  --version VER     Specific version to download (default: latest)"
      echo "  --force           Overwrite existing chart directory"
      echo "  --dry-run         Show what would be done without downloading"
      echo ""
      echo "Examples:"
      echo "  $0 --name alloy                    # Download latest"
      echo "  $0 --name alloy --version 1.3.0    # Download specific version"
      echo "  $0 --name karpenter --version 1.7.0 # OCI chart"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ── Validation ───────────────────────────────────────────────────────────────
if [[ -z "${CHART_NAME}" ]]; then
  echo -e "${RED}Error: --name is required${RESET}" >&2
  echo "Usage: $0 --name <chart> [--version <version>] [--force] [--dry-run]" >&2
  exit 1
fi

for cmd in helm yq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Error: '${cmd}' is required but not installed.${RESET}" >&2
    exit 1
  fi
done

if [[ ! -f "${REGISTRY}" ]]; then
  echo -e "${RED}Error: Chart registry not found at ${REGISTRY}${RESET}" >&2
  exit 1
fi

# ── Lookup chart in registry ─────────────────────────────────────────────────
CHART_INDEX=$(yq ".charts | to_entries | .[] | select(.value.name == \"${CHART_NAME}\") | .key" "${REGISTRY}" 2>/dev/null)

if [[ -z "${CHART_INDEX}" ]]; then
  echo -e "${RED}Error: Chart '${CHART_NAME}' not found in ${REGISTRY}${RESET}" >&2
  echo "Available charts:" >&2
  yq '.charts[].name' "${REGISTRY}" | sort | sed 's/^/  /' >&2
  exit 1
fi

CHART_TYPE=$(yq ".charts[${CHART_INDEX}].type // \"helm\"" "${REGISTRY}")
CHART_REPO=$(yq ".charts[${CHART_INDEX}].repo" "${REGISTRY}")
CHART_IN_REPO=$(yq ".charts[${CHART_INDEX}].chart // \"${CHART_NAME}\"" "${REGISTRY}")
REPO_ALIAS=$(yq ".charts[${CHART_INDEX}].repoAlias // \"\"" "${REGISTRY}")
CURRENT_DIR=$(yq ".charts[${CHART_INDEX}].directory" "${REGISTRY}")
CURRENT_VER=$(yq ".charts[${CHART_INDEX}].version" "${REGISTRY}")
LOCAL_PATCHES=$(yq ".charts[${CHART_INDEX}].localPatches // false" "${REGISTRY}")
PATCH_NOTES=$(yq ".charts[${CHART_INDEX}].patchNotes // \"\"" "${REGISTRY}")
INTERNAL=$(yq ".charts[${CHART_INDEX}].internal // false" "${REGISTRY}")

if [[ "${INTERNAL}" == "true" ]]; then
  echo -e "${YELLOW}Warning: '${CHART_NAME}' is marked as internal — skipping download.${RESET}"
  exit 0
fi

# ── Resolve latest version if not specified ──────────────────────────────────
if [[ -z "${CHART_VERSION}" ]]; then
  echo -e "${CYAN}Resolving latest version for ${CHART_NAME}...${RESET}"
  case "${CHART_TYPE}" in
    helm)
      helm repo add "${REPO_ALIAS}" "${CHART_REPO}" --force-update &>/dev/null
      helm repo update "${REPO_ALIAS}" &>/dev/null
      CHART_VERSION=$(helm search repo "${REPO_ALIAS}/${CHART_IN_REPO}" --output json | \
        yq -p json -r '.[0].version' 2>/dev/null)
      ;;
    oci)
      CHART_VERSION=$(helm show chart "${CHART_REPO}/${CHART_IN_REPO}" 2>/dev/null | \
        yq -r '.version' 2>/dev/null)
      ;;
  esac

  if [[ -z "${CHART_VERSION}" || "${CHART_VERSION}" == "null" ]]; then
    echo -e "${RED}Error: Could not resolve latest version for '${CHART_NAME}'${RESET}" >&2
    exit 1
  fi
  echo -e "  Latest version: ${BOLD}${CHART_VERSION}${RESET}"
fi

# ── Determine target directory name ──────────────────────────────────────────
# Follow existing naming convention from the current directory
# Extract the prefix pattern: everything before the current version in the directory name
DIR_PREFIX="${CURRENT_DIR%-${CURRENT_VER}}"
# Handle cases where version has a 'v' prefix in the dir name (e.g., dragonfly-v1.36.0)
if [[ "${CURRENT_DIR}" == *"-v${CURRENT_VER}"* && "${CHART_VERSION}" != v* ]]; then
  TARGET_DIR="${DIR_PREFIX}-v${CHART_VERSION}"
elif [[ "${CURRENT_DIR}" == *"-${CURRENT_VER}" ]]; then
  TARGET_DIR="${DIR_PREFIX}-${CHART_VERSION}"
else
  # Fallback: use chart name + version
  TARGET_DIR="${CHART_NAME}-${CHART_VERSION}"
fi
TARGET_PATH="${SCRIPT_DIR}/${TARGET_DIR}"

# ── Check if already at target version ───────────────────────────────────────
CURRENT_NORM="${CURRENT_VER#v}"
TARGET_NORM="${CHART_VERSION#v}"

if [[ "${CURRENT_NORM}" == "${TARGET_NORM}" ]]; then
  echo -e "${GREEN}Chart '${CHART_NAME}' is already at version ${CHART_VERSION}${RESET}"
  exit 0
fi

if [[ -d "${TARGET_PATH}" && "${FORCE}" == "false" ]]; then
  echo -e "${YELLOW}Directory ${TARGET_DIR} already exists. Use --force to overwrite.${RESET}"
  exit 1
fi

# ── Show plan ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Download Plan:${RESET}"
echo "  Chart:       ${CHART_NAME}"
echo "  Current:     ${CURRENT_VER} (${CURRENT_DIR})"
echo "  Target:      ${CHART_VERSION} (${TARGET_DIR})"
echo "  Type:        ${CHART_TYPE}"
echo "  Repo:        ${CHART_REPO}"

if [[ "${LOCAL_PATCHES}" == "true" ]]; then
  echo ""
  echo -e "  ${RED}${BOLD}⚠  LOCAL PATCHES — Must be re-applied after download!${RESET}"
  echo -e "  ${YELLOW}${PATCH_NOTES}${RESET}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo ""
  echo -e "${CYAN}Dry run — no changes made.${RESET}"
  exit 0
fi

echo ""

# ── Download ─────────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo -e "${CYAN}Downloading ${CHART_NAME} v${CHART_VERSION}...${RESET}"

case "${CHART_TYPE}" in
  helm)
    helm repo add "${REPO_ALIAS}" "${CHART_REPO}" --force-update &>/dev/null
    helm repo update "${REPO_ALIAS}" &>/dev/null
    helm pull "${REPO_ALIAS}/${CHART_IN_REPO}" \
      --version "${CHART_VERSION}" \
      --untar \
      --untardir "${TMPDIR}"
    ;;
  oci)
    helm pull "${CHART_REPO}/${CHART_IN_REPO}" \
      --version "${CHART_VERSION}" \
      --untar \
      --untardir "${TMPDIR}"
    ;;
esac

# Find the extracted directory (chart name inside the tarball may differ)
EXTRACTED_DIR=$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 -type d | head -1)

if [[ -z "${EXTRACTED_DIR}" || ! -d "${EXTRACTED_DIR}" ]]; then
  echo -e "${RED}Error: Download succeeded but no chart directory found${RESET}" >&2
  exit 1
fi

# ── Move to target location ─────────────────────────────────────────────────
if [[ -d "${TARGET_PATH}" && "${FORCE}" == "true" ]]; then
  echo -e "${YELLOW}Removing existing ${TARGET_DIR}...${RESET}"
  rm -rf "${TARGET_PATH}"
fi

mv "${EXTRACTED_DIR}" "${TARGET_PATH}"

# ── Update registry ──────────────────────────────────────────────────────────
echo -e "${CYAN}Updating chart-registry.yaml...${RESET}"
yq -i ".charts[${CHART_INDEX}].version = \"${CHART_VERSION}\"" "${REGISTRY}"
yq -i ".charts[${CHART_INDEX}].directory = \"${TARGET_DIR}\"" "${REGISTRY}"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ Downloaded ${CHART_NAME} v${CHART_VERSION} → ${TARGET_DIR}${RESET}"
echo ""

if [[ "${LOCAL_PATCHES}" == "true" ]]; then
  echo -e "${RED}${BOLD}ACTION REQUIRED: Re-apply local patches!${RESET}"
  echo -e "${YELLOW}${PATCH_NOTES}${RESET}"
  echo ""
fi

echo "Next steps:"
echo "  1. Review the new chart: diff ${CURRENT_DIR} ${TARGET_DIR}"
if [[ "${LOCAL_PATCHES}" == "true" ]]; then
  echo "  2. Re-apply local patches (see above)"
  echo "  3. Update kustomization.yaml references from ${CURRENT_DIR} to ${TARGET_DIR}"
  echo "  4. Run: helm template charts/${TARGET_DIR} | kubeconform -strict"
  echo "  5. Test in dev environment before promoting"
  echo "  6. Commit all changes"
else
  echo "  2. Update kustomization.yaml references from ${CURRENT_DIR} to ${TARGET_DIR}"
  echo "  3. Run: helm template charts/${TARGET_DIR} | kubeconform -strict"
  echo "  4. Test in dev environment before promoting"
  echo "  5. Commit all changes"
fi