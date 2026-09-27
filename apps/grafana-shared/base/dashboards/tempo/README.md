# Tempo Dashboards (Grafana Operator)

This folder contains GrafanaDashboard CRs that import official Grafana Tempo dashboards.

Dashboards are provisioned through Grafana Operator and grouped under the `Tempo` folder.

## Source of truth

- Grafana Tempo repository:
  - https://github.com/grafana/tempo
- Official compiled mixin assets:
  - https://github.com/grafana/tempo/tree/main/operations/tempo-mixin-compiled
- Dashboard JSON source directory used by this repo:
  - https://github.com/grafana/tempo/tree/main/operations/tempo-mixin-compiled/dashboards

## Dashboards currently imported

All manifests in this folder vendor upstream dashboard JSON directly in `spec.json`:

- `tempo-backendwork.yaml`
- `tempo-block-builder.yaml`
- `tempo-livestore.yaml`
- `tempo-operational.yaml`
- `tempo-reads.yaml`
- `tempo-resources.yaml`
- `tempo-rollout-progress.yaml`
- `tempo-service-graph.yaml`
- `tempo-tenants.yaml`
- `tempo-writes.yaml`

Vendoring these JSON payloads prevents drift from upstream `main` and allows local fixes when needed.

## Datasource mapping conventions in this repo

- Prometheus-compatible inputs map to datasource `mimir`.
- Loki-compatible inputs map to datasource `loki`.
- Some upstream dashboards use different input variable names (`datasource`, `ds`, `metrics`, `logs`, `logsds`), so each CR declares explicit `spec.datasources` mapping.
- Upstream hardcoded datasource UIDs are normalized to dashboard input variables (for example `$ds`) before committing.

## Why these are in GrafanaDashboard CRs

This repo provisions dashboards through Grafana Operator (GrafanaDashboard resources), not by manual UI import.

The resources follow existing repo conventions:

- `dashboards: "grafana"` label
- `instanceSelector.matchLabels.dashboards: "grafana"`
- `argocd.argoproj.io/sync-options: ServerSideApply=true`
- Folder assignment via `folder: "Tempo"`

## Update workflow (future chart/dashboard refresh)

1. Check the deployed Tempo chart/app version and choose an upstream Tempo release/commit to align with.
2. Review changes in upstream `operations/tempo-mixin-compiled/dashboards`.
3. Download dashboard JSON from upstream and replace each manifest `spec.json` payload.
4. Normalize any hardcoded datasource UIDs to dashboard variable UIDs (for example `$ds`/`$logsds`).
5. Re-check dashboard input variable names and keep `spec.datasources` mappings correct.
6. Validate rendering:
   - `kubectl kustomize apps/grafana-shared/base`
7. Sync via Argo CD and smoke test key Tempo dashboards in Grafana.

## Notes

- Current dashboard payloads are vendored snapshots from upstream Tempo mixin JSON.
