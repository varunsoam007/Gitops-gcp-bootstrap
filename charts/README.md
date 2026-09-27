# Cached Helm Charts

All vendored Helm charts are stored in this directory following the `<name>-<version>` naming convention. The canonical list of charts is maintained in [`chart-registry.yaml`](chart-registry.yaml).

## Automated Chart Management

### Check for updates

```bash
# Show all charts and their upstream status
./chart-version-report.sh

# Show only charts with updates available
./chart-version-report.sh --outdated

# Check a specific chart
./chart-version-report.sh --name alloy

# JSON output for scripting
./chart-version-report.sh --json
```

### Download / update a chart

```bash
# Download latest version
./chart-downloader.sh --name alloy

# Download specific version
./chart-downloader.sh --name alloy --version 1.3.0

# Preview without downloading
./chart-downloader.sh --name alloy --dry-run

# Overwrite existing directory
./chart-downloader.sh --name alloy --version 1.3.0 --force
```

The downloader automatically updates `chart-registry.yaml` with the new version and directory name.

### Check rollout status across environments

```bash
# Show chart versions per environment (devm, tstm, prdm, mgt)
./chart-rollout-report.sh

# Show only charts with in-progress rollouts
./chart-rollout-report.sh --rolling-only

# Check a specific chart
./chart-rollout-report.sh --name alloy

# JSON output for scripting
./chart-rollout-report.sh --json
```

The rollout report scans each environment's `kustomization.yaml` files for `helmCharts[].name` references and compares them against `chart-registry.yaml`. No network calls — purely filesystem scan.

**Statuses:** Consistent (all envs match registry), Rolling (mixed versions, mid-rollout), Drift (envs match each other but not the registry), N/A (not deployed to that env).

### Dependencies

Both scripts require:
- `helm` CLI
- [`yq`](https://github.com/mikefarah/yq) v4+ (Mike Farah's YAML processor)

### Prompt file

A step-by-step guide for upgrading charts is available at [`.github/prompts/update-helm-charts.prompt.md`](../.github/prompts/update-helm-charts.prompt.md). This can be used by agents or developers as a checklist.

### chart-registry.yaml

Single source of truth for all vendored charts. Each entry contains:

| Field | Description |
|-------|-------------|
| `name` | Chart name (matches Helm chart name) |
| `directory` | Local directory under `charts/` |
| `version` | Currently vendored version |
| `type` | `helm` (traditional repo) or `oci` (OCI registry) |
| `repo` | Upstream repository URL |
| `chart` | Chart name in the upstream repo (if different from `name`) |
| `repoAlias` | Local Helm repo alias for `helm repo add` |
| `localPatches` | `true` if chart has local modifications |
| `patchNotes` | Description of local patches |
| `internal` | `true` if chart has no upstream |

---

## How to add a new chart manually

### Pull the chart the old way

1. Add the helm repository to your local repo list. E.g. `helm repo add jetstack https://charts.jetstack.io`.
1. Update your local Helm chart repository cache: `helm repo update`
1. Pull the desired chart: `helm pull jetstack/cert-manager`

### Pull the chart from an OCI registry

1. Pull the chart using the OCI URL. E.g. `helm pull oci://mcr.microsoft.com/aks/karpenter/karpenter --version 1.4.0`

### Untar the package

1. Extract the chart: `tar xzf karpenter-1.4.0.tgz`
1. Rename the directory to represent the repo and the version as well: `mv karpenter karpenter-1.4.0`

This is a good practice that supports competing versions running for an upgrade or even for a progressive rollout.

# 3rd Party Chart sources
Index of 3rd party chart sources

## Prometheus
Chart Name: Prometheus<br>
Source: https://github.com/prometheus-community/helm-charts <br>
Chart Repo: https://prometheus-community.github.io/helm-charts <br>
Pull usage: ```helm pull prometheus-community/kube-prometheus-stack``` <br>


## Istio
Source: https://github.com/istio/istio/tree/master/manifests/charts <br>
Add repo: ```helm repo add istio https://istio-release.storage.googleapis.com/charts``` <br>
List charts: ```helm search repo istio``` <br>
Pull usage: ```helm pull istio/ambient``` <br>

The Ambient chart includes the 4 sub charts required for Istio:
- Base
- CNI
- Istiod
- Ztunnel

## Kiali
Chart Name: Kiali<br>
Source: https://github.com/kiali/helm-charts <br>
Chart Repo: https://kiali.github.io/helm-charts <br>
Pull usage: ```helm pull kiali/kiali-server``` <br>

Steps: ```helm repo add kiali https://kiali.github.io/helm-charts```

## Kargo
Chart Name: Kargo<br>
Source: https://github.com/kargo/helm-charts <br>
Chart Repo: https://kargo.github.io/helm-charts <br>
Pull usage: ```helm pull oci://ghcr.io/akuity/kargo-charts/kargo --version 1.7.5``` <br>
untar: ```tar xzf kargo-1.7.5.tgz```

## Exteral-dns
Chart Name: external-dns<br>
Source: https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns <br>
Chart Repo: https://kubernetes-sigs.github.io/external-dns <br>
Pull usage: ```helm pull external-dns/external-dns``` <br>

Steps: ```helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/```
untar: ```tar xzf external-dns-1.19.0.tgz ```


## Exteral-secrets
Chart Name: external-secrets<br>
Source: https://github.com/external-secrets/external-secrets/tree/main/deploy/charts/external-secrets <br>
Chart Repo: https://charts.external-secrets.io <br>
Pull usage: ```helm pull external-secrets/external-secrets --version 0.20.4``` <br>

Steps: ```helm repo add external-secrets https://charts.external-secrets.io```<br>
untar: ```tar xzf external-secrets-0.20.4.tgz ```

## Falco
Chart Name: Falco<br>
Source: https://github.com/falcosecurity/charts/tree/master/charts/falco <br>
Chart Repo: https://falcosecurity.github.io/charts <br>
Pull usage: ```helm pull falcosecurity/falco --version 7.0.2``` <br>

Steps: 
```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm pull falcosecurity/falco --version 7.0.2
tar xzf falco-7.0.2.tgz
mv falco falco-7.0.2
```

## Prometheus Blackbox Exporter
Chart Name: prometheus-blackbox-exporter<br>
Source: https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-blackbox-exporter <br>
Chart Repo: https://prometheus-community.github.io/helm-charts <br>
Pull usage: ```helm pull prometheus-community/prometheus-blackbox-exporter --version 11.6.1``` <br>

Steps:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm pull prometheus-community/prometheus-blackbox-exporter --version 11.6.1 --untar
# Chart directory is named 'prometheus-blackbox-exporter' by default
```
