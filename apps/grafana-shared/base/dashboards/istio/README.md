# Istio Dashboards (Grafana Operator)

This folder contains GrafanaDashboard CRs for Istio monitoring, including ambient mesh coverage.

## Source of truth

- Istio upstream dashboard assets:
  - https://github.com/istio/istio/tree/release-1.29/manifests/addons/dashboards

## Dashboards in this folder

- `istio-control-plane.yaml`
- `istio-mesh.yaml`
- `istio-service.yaml`
- `istio-workload.yaml`
- `istio-ambient-ztunnel.yaml`

## Ambient mesh coverage

Ambient-specific coverage is provided by:

- `istio-ambient-ztunnel.yaml` (imports `ztunnel-dashboard.gen.json` from Istio upstream)

The existing mesh/service/workload dashboards in this folder already include waypoint-aware traffic queries.

## Why these are in GrafanaDashboard CRs

This repo provisions dashboards through Grafana Operator (GrafanaDashboard resources), not by manual UI import.

The resources follow repo conventions:

- `dashboards: "grafana"` label
- `instanceSelector.matchLabels.dashboards: "grafana"`
- `argocd.argoproj.io/sync-options: ServerSideApply=true`
- Folder assignment: `Platform Components`

## Update workflow

1. Align updates with deployed Istio release line.
2. For upstream imports, update URL branch/version if needed.
3. Keep datasource mappings intact unless upstream input names change.
4. Validate render:
   - `kubectl kustomize apps/grafana-shared/base/dashboards`
