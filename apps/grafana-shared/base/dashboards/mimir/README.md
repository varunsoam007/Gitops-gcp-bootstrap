# Mimir Dashboards (Grafana Operator)

This folder contains GrafanaDashboard CRs generated from the official Grafana Mimir compiled dashboards.

These dashboards are expected to be deployed together with the matching Mimir mixin recording rules and alerts.

## Source of truth

- Compiled dashboard JSON files:
  - https://github.com/grafana/mimir/tree/main/operations/mimir-mixin-compiled/dashboards
- Compiled recording rules:
  - https://github.com/grafana/mimir/blob/main/operations/mimir-mixin-compiled/rules.yaml
- Compiled alerts:
  - https://github.com/grafana/mimir/blob/main/operations/mimir-mixin-compiled/alerts.yaml
- File index API (used to discover dashboard names):
  - https://api.github.com/repos/grafana/mimir/contents/operations/mimir-mixin-compiled/dashboards?ref=main

## Official source for required rules and alerts

If you need the complete list of dashboard-required recording rules and alert definitions, use these as the authoritative sources:

- Mimir docs (installation + requirements):
  - https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/installing-dashboards-and-alerts/
  - https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/requirements/
- Mimir mixin source (versioned rule logic):
  - https://github.com/grafana/mimir/blob/main/operations/mimir-mixin/recording_rules.libsonnet
  - https://github.com/grafana/mimir/blob/main/operations/mimir-mixin/alerts.libsonnet

Important: dashboards, recording rules, and alerts should be version-matched from the same Mimir release/mixin revision.

## Documentation references used

- Monitor system health:
  - https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/monitor-system-health/
- Install dashboards and alerts:
  - https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/installing-dashboards-and-alerts/
- Dashboard and alert requirements (labels, scrape interval, job naming):
  - https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/requirements/
- Kubernetes Monitoring Helm integration (context only):
  - https://github.com/grafana/k8s-monitoring-helm/blob/main/charts/k8s-monitoring/charts/feature-integrations/docs/integrations/mimir.md

## Why these are in GrafanaDashboard CRs

This repo provisions dashboards through Grafana Operator (GrafanaDashboard resources), not by manual UI import.

Alerts and recording rules are not deployed as PrometheusRule objects in this repo; they are loaded into Mimir ruler via [apps/mimir/base/mimir-ruler-rules.yaml](apps/mimir/base/mimir-ruler-rules.yaml).

The generated resources follow the existing repo pattern:

- `dashboards: "grafana"` label
- `instanceSelector.matchLabels.dashboards: "grafana"`
- `argocd.argoproj.io/sync-options: ServerSideApply=true`
- Folder assignment: `Mimir`

## Update workflow (for future agents)

When Mimir dashboards need updating (for new Mimir release/mixin changes), update dashboards/rules/alerts together:

1. Choose a single Mimir mixin revision/release.
2. Fetch current compiled dashboard filenames from Grafana Mimir repo.
3. Download each dashboard JSON from `operations/mimir-mixin-compiled/dashboards`.
4. Regenerate each GrafanaDashboard CR in this folder with:
   - metadata labels and annotations matching repo conventions
   - `folder: "Mimir"`
   - raw dashboard JSON under `spec.json: |`
5. Align [apps/mimir/base/mimir-ruler-rules.yaml](apps/mimir/base/mimir-ruler-rules.yaml) with compiled mixin recording rules and alerts (or clearly document intentional deviations).
6. Refresh this folder's `kustomization.yaml` resource list.
7. Validate render:
   - `kubectl kustomize apps/grafana-shared/base/dashboards`
  - `kubectl kustomize apps/mimir/base`
8. Commit as a single logical change.

## Known operational requirements

Official Mimir dashboards/alerts assume specific labels and scrape behavior.

Important checks before/after update:

- Metrics include expected labels (`cluster`, `namespace`, `job`, `pod`, `instance`).
- `job` naming matches Mimir microservices expectations from docs.
- Scrape interval for Mimir metrics is aligned with Grafana recommendations for alerts/rules fidelity (15s or faster where required).
- Datasource mapping in Grafana is valid for dashboards using `$datasource` variables.

### Current compatibility implementation in this repo

- Mimir dashboard CRs: this folder.
- Mimir ruler rule/alert payload: [apps/mimir/base/mimir-ruler-rules.yaml](apps/mimir/base/mimir-ruler-rules.yaml).
- Job-label normalization for Mimir self-scrape targets: [apps/alloy/base/servicemonitors.yaml](apps/alloy/base/servicemonitors.yaml).

## Files in this folder

- `folder-mimir.yaml`: Grafana folder resource.
- `mimir-*.yaml`: Generated GrafanaDashboard CRs from official compiled JSON.
- `kustomization.yaml`: Resource list consumed by parent dashboards kustomization.
