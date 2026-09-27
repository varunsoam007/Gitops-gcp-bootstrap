#!/usr/bin/env bash
# renovate-post-upgrade.sh — Vendor new chart + update kustomization refs
# Called by Renovate postUpgradeTasks after bumping a version in chart-registry.yaml
#
# Usage: bash charts/renovate-post-upgrade.sh <dep-name> <old-version> <new-version>
#
# This script:
#   1. Downloads the new chart version via helm
#   2. Places it alongside the old chart (old kept for other envs)
#   3. Updates the directory field in chart-registry.yaml
#   4. Updates dev kustomization refs, plus mgt refs for mgt-only apps
#
# Dependencies: helm, bash, awk, sed, find

set -euo pipefail

DEP_NAME_RAW="${1:?Usage: $0 <dep-name> <old-version> <new-version>}"
OLD_VERSION="${2:?Missing old-version}"
NEW_VERSION="${3:?Missing new-version}"

# OCI depNames are multi-segment (e.g. aks/karpenter/karpenter) — extract the
# last segment to match the 'name' field in chart-registry.yaml
DEP_NAME="${DEP_NAME_RAW##*/}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/chart-registry.yaml"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Helper: extract field from chart-registry.yaml for a given chart ─────────
get_field() {
  local name="$1" field="$2"
  awk -v n="$name" -v f="${field}:" '
    /^  - name:/ { blk = ($NF == n) }
    blk && index($0, f) {
      val = substr($0, index($0, f) + length(f))
      gsub(/^[[:space:]]+/, "", val)
      gsub(/[[:space:]]*#.*$/, "", val)
      gsub(/^"|"$/, "", val)
      print val; exit
    }
  ' "$REGISTRY"
}

# ── Read chart metadata from registry ────────────────────────────────────────
OLD_DIR=$(get_field "$DEP_NAME" "directory")
if [[ -z "$OLD_DIR" ]]; then
  echo "ERROR: chart '$DEP_NAME' not found in chart-registry.yaml" >&2
  exit 1
fi

CHART_TYPE=$(get_field "$DEP_NAME" "type")
CHART_TYPE="${CHART_TYPE:-helm}"
CHART_REPO=$(get_field "$DEP_NAME" "repo")
CHART_IN_REPO=$(get_field "$DEP_NAME" "chart")
CHART_IN_REPO="${CHART_IN_REPO:-$DEP_NAME}"
REPO_ALIAS=$(get_field "$DEP_NAME" "repoAlias")
LOCAL_PATCHES=$(get_field "$DEP_NAME" "localPatches")

# ── Compute new directory name ───────────────────────────────────────────────
NEW_DIR="${OLD_DIR/$OLD_VERSION/$NEW_VERSION}"

if [[ "$OLD_DIR" == "$NEW_DIR" ]]; then
  echo "ERROR: could not derive new directory (old=$OLD_DIR, sub $OLD_VERSION → $NEW_VERSION)" >&2
  exit 1
fi

echo "==> Upgrading $DEP_NAME: $OLD_DIR → $NEW_DIR"

# ── Download new chart ───────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

case "$CHART_TYPE" in
  helm)
    if [[ -n "$REPO_ALIAS" && -n "$CHART_REPO" ]]; then
      helm repo add "$REPO_ALIAS" "$CHART_REPO" --force-update >/dev/null 2>&1 || true
      helm repo update "$REPO_ALIAS" >/dev/null 2>&1 || true
      helm pull "${REPO_ALIAS}/${CHART_IN_REPO}" \
        --version "$NEW_VERSION" --untar --untardir "$TMPDIR"
    else
      echo "ERROR: helm chart needs repoAlias and repo fields" >&2
      exit 1
    fi
    ;;
  oci)
    helm pull "${CHART_REPO}/${CHART_IN_REPO}" \
      --version "$NEW_VERSION" --untar --untardir "$TMPDIR"
    ;;
  *)
    echo "ERROR: unknown chart type '$CHART_TYPE'" >&2
    exit 1
    ;;
esac

EXTRACTED=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -z "$EXTRACTED" || ! -d "$EXTRACTED" ]]; then
  echo "ERROR: helm pull succeeded but no chart directory found" >&2
  exit 1
fi

# ── Place new chart, keep old for other envs ─────────────────────────────────
rm -rf "${SCRIPT_DIR:?}/${NEW_DIR}"
mv "$EXTRACTED" "${SCRIPT_DIR}/${NEW_DIR}"

# Don't delete the old chart directory — non-dev environments (tst, prd)
# still reference it until the change is promoted through those envs.

# ── Update directory field in chart-registry.yaml ────────────────────────────
sed -i "s|directory: ${OLD_DIR}$|directory: ${NEW_DIR}|" "$REGISTRY"

# ── Update kustomization.yaml references ─────────────────────────────────────
# Update devm-k01 overlays by default.
# For standalone apps that only run in mgt (no devm overlay), update mgt-k01.
UPDATED=0

CANDIDATE_KUSTOMIZATIONS=()

while IFS= read -r kust; do
  CANDIDATE_KUSTOMIZATIONS+=("$kust")
done < <(find "${REPO_ROOT}/apps" -path "*/envs/devm-k01/kustomization.yaml" 2>/dev/null)

while IFS= read -r kust; do
  APP_DIR="${kust%/envs/mgt-k01/kustomization.yaml}"
  if [[ ! -f "${APP_DIR}/envs/devm-k01/kustomization.yaml" ]]; then
    CANDIDATE_KUSTOMIZATIONS+=("$kust")
  fi
done < <(find "${REPO_ROOT}/apps" -path "*/envs/mgt-k01/kustomization.yaml" 2>/dev/null)

for kust in "${CANDIDATE_KUSTOMIZATIONS[@]}"; do
  if grep -q "name: ${OLD_DIR}" "$kust"; then
    sed -i "s|name: ${OLD_DIR}|name: ${NEW_DIR}|g" "$kust"
    # also update the version: field if present (kustomize helmCharts)
    sed -i "s|version: ${OLD_VERSION}|version: ${NEW_VERSION}|g" "$kust"
    UPDATED=$((UPDATED + 1))
    echo "  Updated: ${kust#"${REPO_ROOT}/"}"
  fi
done

if [[ "$UPDATED" -eq 0 ]]; then
  echo "WARNING: no kustomization.yaml refs found for ${OLD_DIR} in devm-k01 or mgt-only overlays"
fi

# ── Clean up orphaned old chart if no env references it ──────────────────────
# After promoting through all envs, the old chart dir becomes unused.
# Check all kustomization.yaml files in the repo — if none reference the old dir, remove it.
if [[ "$OLD_DIR" != "$NEW_DIR" && -d "${SCRIPT_DIR}/${OLD_DIR}" ]]; then
  if ! grep -rq "name: ${OLD_DIR}" "${REPO_ROOT}/apps/" 2>/dev/null; then
    rm -rf "${SCRIPT_DIR:?}/${OLD_DIR}"
    echo "  Cleaned up orphaned chart: ${OLD_DIR} (no kustomization refs found)"
  else
    echo "  Keeping old chart: ${OLD_DIR} (still referenced by other envs)"
  fi
fi

echo "==> Done: $DEP_NAME $OLD_VERSION → $NEW_VERSION"

# ── Warn about local patches ────────────────────────────────────────────────
if [[ "$LOCAL_PATCHES" == "true" ]]; then
  PATCH_NOTES=$(get_field "$DEP_NAME" "patchNotes")
  echo ""
  echo "WARNING: $DEP_NAME has local patches that must be re-applied!"
  echo "Patch notes: $PATCH_NOTES"
  echo "Review the PR carefully and re-apply patches before merging."
fi
